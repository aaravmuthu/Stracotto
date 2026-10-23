import Foundation
import IOKit
import IOKit.ps
import Observation

/// What the battery is doing right now. Maps to the four live menu bar icons.
enum PowerState: Equatable, Sendable {
    case charging        // plugged in, battery filling
    case paused          // plugged in, battery holding (full, or macOS optimized charging)
    case pluggedDraining // plugged in, but the charger can't keep up
    case onBattery       // unplugged
}

struct BatterySnapshot: Equatable, Sendable {
    var percent = 0
    /// Gas-gauge reading (RemainingCapacity / FullChargeCapacity), shown next to the macOS value.
    var hardwarePercent: Double = 0
    var state = PowerState.onBattery
    var isPluggedIn = false
    var minutesRemaining: Int?
    var cycleCount = 0
    var designCycleCount = 0
    var health: Int?
    var condition = "Normal"
    var designCapacity = 0       // mAh
    var fullChargeCapacity = 0   // mAh
    var remainingCapacity = 0    // mAh
    var temperature: Double?     // °C
    var voltage: Double = 0      // V
    var amperage: Double = 0     // A, negative while discharging
    var adapterWatts: Int?
    var adapterName: String?
    var lowPowerMode = false
    var flow = PowerFlow()
}

/// Watts moving between charger, battery and system. All values ≥ 0.
struct PowerFlow: Equatable, Sendable {
    var adapterToSystem: Double = 0
    var adapterToBattery: Double = 0
    var batteryToSystem: Double = 0
    var systemLoad: Double = 0
    var adapterIn: Double { adapterToSystem + adapterToBattery }
}

@MainActor @Observable
final class BatteryMonitor {
    private(set) var snapshot = BatterySnapshot()
    private(set) var history: [Sample] = []

    struct Sample: Identifiable, Sendable { let id = UUID(); let date: Date; let percent: Int; let watts: Double }

    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    private var healthTask: Task<Void, Never>?
    private var cachedHealth: (value: Int, condition: String)?

    init() {
        refresh()
        start()
    }

    /// Fixed data for snapshots; never polls.
    init(fixed: BatterySnapshot) { snapshot = fixed }

    private func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // Plug/unplug lands instantly instead of waiting for the next tick.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                let health = await Self.readSystemHealth()
                self?.cachedHealth = health
                self?.refresh()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    func refresh() {
        guard var s = Self.readRegistry() else { return }
        if let cachedHealth {
            s.health = cachedHealth.value
            s.condition = cachedHealth.condition
        } else if s.designCapacity > 0 {
            s.health = Int((Double(s.fullChargeCapacity) / Double(s.designCapacity) * 100).rounded())
        }
        s.temperature = Self.smcTemperature() ?? s.temperature
        s.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        snapshot = s

        let now = Date()
        if history.last.map({ now.timeIntervalSince($0.date) >= 60 }) ?? true {
            history.append(Sample(date: now, percent: s.percent, watts: s.flow.systemLoad))
            if history.count > 24 * 60 { history.removeFirst(history.count - 24 * 60) }
        }
    }

    // MARK: - IOKit

    private static func readRegistry() -> BatterySnapshot? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == kIOReturnSuccess,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }

        func int(_ d: [String: Any], _ k: String) -> Int? { (d[k] as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) } }
        let battery = props["BatteryData"] as? [String: Any] ?? [:]
        let telemetry = props["PowerTelemetryData"] as? [String: Any] ?? [:]
        let adapter = props["AdapterDetails"] as? [String: Any] ?? [:]

        var s = BatterySnapshot()
        s.percent = int(props, "CurrentCapacity") ?? 0
        s.isPluggedIn = props["ExternalConnected"] as? Bool ?? false
        let charging = props["IsCharging"] as? Bool ?? false
        s.cycleCount = int(props, "CycleCount") ?? 0
        s.designCycleCount = int(props, "DesignCycleCount9C") ?? 1000
        s.designCapacity = int(props, "DesignCapacity") ?? int(battery, "DesignCapacity") ?? 0
        s.fullChargeCapacity = int(props, "AppleRawMaxCapacity") ?? int(battery, "FullChargeCapacity") ?? 0
        s.remainingCapacity = int(props, "AppleRawCurrentCapacity") ?? int(battery, "RemainingCapacity") ?? 0
        if s.fullChargeCapacity > 0 { s.hardwarePercent = Double(s.remainingCapacity) / Double(s.fullChargeCapacity) * 100 }
        s.voltage = Double(int(props, "Voltage") ?? 0) / 1000
        s.amperage = Double(int(props, "InstantAmperage") ?? int(props, "Amperage") ?? 0) / 1000
        if let t = int(props, "Temperature") { s.temperature = Double(t) / 100 }
        if let w = int(adapter, "Watts"), w > 0 { s.adapterWatts = w }
        s.adapterName = adapter["Name"] as? String

        // Signed mW: BatteryPower > 0 means the battery is filling.
        let load = Double(int(telemetry, "SystemLoad") ?? 0) / 1000
        let batteryPower = Double(int(telemetry, "BatteryPower") ?? int(battery, "BatteryPower") ?? 0) / 1000
        let wallIn = Double(int(telemetry, "SystemPowerIn") ?? 0) / 1000
        var flow = PowerFlow(systemLoad: max(load, 0))
        if s.isPluggedIn {
            flow.adapterToBattery = max(batteryPower, 0)
            flow.batteryToSystem = max(-batteryPower, 0)
            flow.adapterToSystem = max(min(wallIn - flow.adapterToBattery, flow.systemLoad), 0)
            if flow.adapterToSystem == 0, wallIn == 0 { flow.adapterToSystem = max(flow.systemLoad - flow.batteryToSystem, 0) }
        } else {
            flow.batteryToSystem = max(-batteryPower, flow.systemLoad)
        }
        s.flow = flow

        s.state = switch (s.isPluggedIn, charging) {
        case (false, _): .onBattery
        case (true, true): .charging
        case (true, false): flow.batteryToSystem > 0.5 ? .pluggedDraining : .paused
        }

        let minutes = s.state == .charging ? int(props, "AvgTimeToFull") : int(props, "TimeRemaining") ?? int(props, "AvgTimeToEmpty")
        if let minutes, minutes > 0, minutes < 65535, s.state != .paused { s.minutesRemaining = minutes }
        return s
    }

    // MARK: - SMC

    private static let temperatureKeys = ["TB0T", "TB1T", "TB2T"]

    /// Average of the pack's thermistors; IOKit's Temperature field is missing on some Apple silicon Macs.
    private static func smcTemperature() -> Double? {
        guard let smc = SMC.shared else { return nil }
        let readings = temperatureKeys.compactMap { smc.number($0) }.filter { $0 > 0 && $0 < 100 }
        return readings.isEmpty ? nil : readings.reduce(0, +) / Double(readings.count)
    }

    // MARK: - Health

    /// macOS's "Maximum Capacity" isn't a raw registry field, so ask system_profiler for the exact figure Settings shows.
    nonisolated private static func readSystemHealth() async -> (value: Int, condition: String)? {
        await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPPowerDataType", "-json"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = json["SPPowerDataType"] as? [[String: Any]] else { return nil }
            for entry in entries {
                guard let health = entry["sppower_battery_health_info"] as? [String: Any],
                      let raw = health["sppower_battery_health_maximum_capacity"] as? String,
                      let value = Int(raw.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { continue }
                return (value, health["sppower_battery_health"] as? String ?? "Normal")
            }
            return nil
        }.value
    }
}
