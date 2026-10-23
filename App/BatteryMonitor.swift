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
    var adapterVoltage: Double?  // V negotiated
    var adapterCurrent: Double?  // A max
    var lowPowerMode = false
    var flow = PowerFlow()
}

/// Watts moving between charger, battery and system. All values ≥ 0.
struct PowerFlow: Equatable, Sendable {
    var adapterToSystem: Double = 0
    var adapterToBattery: Double = 0
    var batteryToSystem: Double = 0
    var systemLoad: Double = 0
    /// Per-consumer breakdown for the second stage of the flow; nil until a verified source exists.
    var soc: Double?
    var display: Double?
    var adapterIn: Double { adapterToSystem + adapterToBattery }

    func easing(toward target: PowerFlow, by k: Double = 0.55) -> PowerFlow {
        func ease(_ a: Double, _ b: Double) -> Double { ((a + (b - a) * k) * 100).rounded() / 100 }
        func ease(_ a: Double?, _ b: Double?) -> Double? { b.map { ease(a ?? $0, $0) } }
        return PowerFlow(adapterToSystem: ease(adapterToSystem, target.adapterToSystem),
                         adapterToBattery: ease(adapterToBattery, target.adapterToBattery),
                         batteryToSystem: ease(batteryToSystem, target.batteryToSystem),
                         systemLoad: ease(systemLoad, target.systemLoad),
                         soc: ease(soc, target.soc), display: ease(display, target.display))
    }
}

@MainActor @Observable
final class BatteryMonitor {
    private(set) var snapshot = BatterySnapshot()
    private(set) var history: [Sample] = []
    /// Counts charger connections since launch; views replay their plug-in animation when it changes.
    private(set) var plugEvents = 0
    /// Called after every refresh; the charge controller listens here.
    @ObservationIgnored var onUpdate: ((BatterySnapshot) -> Void)?
    /// The level charging stops at (charge limit, or 100 during Top Up); time-to-full counts to this, not to 100 %.
    @ObservationIgnored var chargeTarget: () -> Int = { 100 }
    /// Current averaged over ~1 minute (EMA), so time remaining doesn't swing with every momentary spike.
    @ObservationIgnored private var avgCurrent: Double?

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
        // PHPC tracks CPU/GPU load (3 W idle → 13 W under load on an M3); used as the SoC branch of the flow.
        if let soc = SMC.shared?.number("PHPC"), soc > 0, soc < s.flow.systemLoad { s.flow.soc = soc }
        s.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        if s.isPluggedIn && !snapshot.isPluggedIn && !history.isEmpty { plugEvents += 1 }
        // Ease the flow toward the new reading so the diagram glides; jump straight there when power state changes.
        if s.state == snapshot.state { s.flow = snapshot.flow.easing(toward: s.flow) }
        s.minutesRemaining = estimateMinutes(s) ?? s.minutesRemaining
        snapshot = s
        onUpdate?(s)

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
        if let v = int(adapter, "AdapterVoltage"), v > 0 { s.adapterVoltage = Double(v) / 1000 }
        if let c = int(adapter, "Current"), c > 0 { s.adapterCurrent = Double(c) / 1000 }

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

    // MARK: - Time remaining

    /// Time remaining, from the battery's own gas gauge (it averages current over about a minute, so it's steadier and
    /// more accurate than any instantaneous reading).
    /// - On battery: the gauge's time-to-empty as is.
    /// - Charging: the gauge reports time to 100 %; this rescales it to the charge limit using the gauge's own charge
    ///   rate, so with an 80 % limit you see the time until charging actually stops.
    /// Falls back to a ~30 s averaged current from the raw reading when the gauge has no estimate yet.
    private func estimateMinutes(_ s: BatterySnapshot) -> Int? {
        let current = s.amperage * 1000   // mA, negative while discharging
        if s.state != snapshot.state || avgCurrent.map({ ($0 < 0) != (current < 0) }) == true { avgCurrent = nil }
        avgCurrent = avgCurrent.map { $0 + (current - $0) * 0.07 } ?? current
        let remaining = Double(s.remainingCapacity), full = Double(s.fullChargeCapacity)
        guard full > 0 else { return s.minutesRemaining }

        switch s.state {
        case .paused:
            return nil
        case .onBattery, .pluggedDraining:
            if let gauge = s.minutesRemaining { return gauge }
            guard let avg = avgCurrent, avg < -50 else { return nil }
            return Int((remaining / -avg * 60).rounded())
        case .charging:
            let target = full * Double(chargeTarget()) / 100
            let toGo = target - remaining
            guard toGo > 0 else { return nil }
            // mAh per minute: from the gauge's time-to-full if it has one, else from averaged current.
            let rate: Double
            if let toFull = s.minutesRemaining, toFull > 0 { rate = (full - remaining) / Double(toFull) }
            else if let avg = avgCurrent, avg > 50 { rate = avg / 60 }
            else { return nil }
            let minutes = toGo / rate
            return minutes.isFinite && minutes > 0 && minutes < 60 * 24 ? max(Int(minutes.rounded()), 1) : nil
        }
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
