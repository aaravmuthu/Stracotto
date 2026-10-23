import AppKit
import Darwin
import Observation

/// Per-app power from the kernel's energy counters (rusage ri_energy_nj), the same source Activity Monitor uses.
/// Readable for every process the user owns; root daemons are skipped, which is fine since they aren't "apps".
@MainActor @Observable
final class EnergyMonitor {
    struct AppEnergy: Identifiable, Equatable {
        let id: String          // bundle path, or executable path for bare processes
        let name: String
        var watts: Double
        @MainActor var icon: NSImage { EnergyMonitor.icon(for: id) }
        var isApp: Bool { id.hasSuffix(".app") }

        /// Asks the app to quit normally (it can still save or refuse), like AlDente's Quit button.
        @MainActor func quit() {
            NSWorkspace.shared.runningApplications
                .filter { $0.bundleURL?.path == id }
                .forEach { $0.terminate() }
        }
    }

    private static var icons: [String: NSImage] = [:]

    /// Workspace icons carry a dozen representations; flatten each to one small bitmap once instead of per frame.
    static func icon(for path: String) -> NSImage {
        if let cached = icons[path] { return cached }
        let source = NSWorkspace.shared.icon(forFile: path)
        let side = 40
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.addRepresentation(rep)
        icons[path] = image
        return image
    }

    /// Apps above `significant`, heaviest first.
    private(set) var heavyApps: [AppEnergy] = []
    /// Every app drawing measurable power, heaviest first, for the Power Flow node details.
    private(set) var topApps: [AppEnergy] = []
    /// True while some app is pulling hard enough to warn about in the menu bar.
    private(set) var isHot = false

    static let significant = 1.0  // W, smoothed
    static let hot = 4.0          // W, smoothed

    private var smoothed: [String: (name: String, watts: Double)] = [:]
    private var task: Task<Void, Never>?

    init() {
        task = Task { [weak self] in
            var previous = await Self.sample()
            var previousTime = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                let current = await Self.sample()
                let now = ContinuousClock.now
                let seconds = Double((now - previousTime).components.seconds) + Double((now - previousTime).components.attoseconds) / 1e18
                self?.ingest(previous: previous, current: current, seconds: seconds)
                (previous, previousTime) = (current, now)
            }
        }
    }

    init(fixed: [AppEnergy]) {
        heavyApps = fixed
        isHot = fixed.contains { $0.watts >= Self.hot }
    }

    private func ingest(previous: [pid_t: Reading], current: [pid_t: Reading], seconds: Double) {
        guard seconds > 0 else { return }
        var perApp: [String: (name: String, watts: Double)] = [:]
        for (pid, now) in current {
            guard let before = previous[pid], before.app.id == now.app.id, now.energy >= before.energy else { continue }
            let watts = Double(now.energy - before.energy) / 1e9 / seconds
            perApp[now.app.id, default: (now.app.name, 0)].watts += watts
        }
        // Exponential smoothing so one spike doesn't flash a warning, and a quiet app fades out instead of vanishing.
        var next: [String: (name: String, watts: Double)] = [:]
        for id in Set(perApp.keys).union(smoothed.keys) {
            let raw = perApp[id]?.watts ?? 0
            let old = smoothed[id]?.watts ?? raw
            let value = old + (raw - old) * 0.45
            if value > 0.05 { next[id] = (perApp[id]?.name ?? smoothed[id]!.name, value) }
        }
        smoothed = next
        topApps = next
            .filter { $0.key != Bundle.main.bundlePath && $0.value.watts >= 0.05 }
            .map { AppEnergy(id: $0.key, name: $0.value.name, watts: $0.value.watts) }
            .sorted { $0.watts > $1.watts }
            .prefix(8)
            .map { $0 }
        heavyApps = next
            .filter { $0.value.watts >= Self.significant && $0.key != Bundle.main.bundlePath }
            // Bare daemons only show when the user asks for background processes, like AlDente 1.39.
            .filter { UserDefaults.standard.bool(forKey: AppearancePrefs.showBackgroundProcesses) || $0.key.hasSuffix(".app") }
            .map { AppEnergy(id: $0.key, name: $0.value.name, watts: $0.value.watts) }
            .sorted { $0.watts > $1.watts }
            .prefix(5)
            .map { $0 }
        isHot = heavyApps.first.map { $0.watts >= Self.hot } ?? false
    }

    // MARK: - Sampling

    struct Reading: Sendable { let energy: UInt64; let app: (id: String, name: String) }

    nonisolated private static func sample() async -> [pid_t: Reading] {
        await Task.detached(priority: .utility) {
            let count = proc_listallpids(nil, 0)
            guard count > 0 else { return [:] }
            var pids = [pid_t](repeating: 0, count: Int(count) + 64)
            let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
            var readings: [pid_t: Reading] = [:]
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            for pid in pids.prefix(Int(max(n, 0))) where pid > 0 {
                var info = rusage_info_v6()
                let r = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V6, $0) }
                }
                guard r == 0, proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { continue }
                readings[pid] = Reading(energy: info.ri_energy_nj, app: owningApp(String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)))
            }
            return readings
        }.value
    }

    /// Folds helpers into the app the user knows: ".../Google Chrome.app/.../Google Chrome Helper.app/..." → Google Chrome.
    nonisolated static func owningApp(_ executable: String) -> (id: String, name: String) {
        if let range = executable.range(of: ".app/") {
            let bundle = String(executable[..<range.lowerBound]) + ".app"
            let name = FileManager.default.displayName(atPath: bundle).replacingOccurrences(of: ".app", with: "")
            return (bundle, name)
        }
        return (executable, (executable as NSString).lastPathComponent)
    }
}
