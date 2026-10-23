import AppKit
import SwiftUI

extension PowerFlowView.Node {
    var detailTitle: String {
        switch self {
        case .adapter: "Charger"
        case .batteryOut, .batteryIn: "Battery"
        case .mac: "This Mac"
        case .soc: ChipInfo.name
        case .display: "Display"
        case .other: "Everything Else"
        }
    }
}

/// What's behind one Power Flow node: tap the CPU to see the chip and the apps working it, the display for its
/// brightness and panel, the battery or charger for their live numbers.
struct NodeDetailView: View {
    let node: PowerFlowView.Node
    let flow: PowerFlow
    @Environment(BatteryMonitor.self) private var battery
    @Environment(EnergyMonitor.self) private var energy

    var body: some View {
        let s = battery.snapshot
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 20)).foregroundStyle(tint).frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(node.detailTitle).font(.system(size: 15, weight: .semibold))
                    if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 16)
                if let watts { Text(PowerFlowView.watts(watts)).font(.system(size: 17, weight: .bold)).monospacedDigit()
                    .contentTransition(.numericText(value: watts)) }
            }
            Divider()
            switch node {
            case .soc, .mac, .other:
                if node == .soc { rows([("Cores", ChipInfo.cores), ("Memory", ChipInfo.memory),
                                        ("Share of system load", percent(flow.soc, of: flow.systemLoad))]) }
                if node == .mac { rows([("Total load", PowerFlowView.watts(flow.systemLoad)),
                                        ("From charger", PowerFlowView.watts(flow.adapterToSystem)),
                                        ("From battery", PowerFlowView.watts(flow.batteryToSystem))]) }
                if node == .other { Text("Memory, storage, Wi-Fi, speakers, keyboard backlight and everything not measured separately.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                appList
            case .display:
                rows(DisplayInfo.rows())
            case .batteryOut, .batteryIn:
                rows([("Charge", "\(s.percent)%"),
                      ("Remaining", "\(s.remainingCapacity) of \(s.fullChargeCapacity) mAh"),
                      ("Current", s.amperage.formatted(.number.precision(.fractionLength(2))) + " A"),
                      ("Voltage", s.voltage.formatted(.number.precision(.fractionLength(2))) + " V"),
                      ("Temperature", s.temperature.map { Measurement(value: $0, unit: UnitTemperature.celsius)
                          .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(1)))) } ?? "--"),
                      ("Health", s.health.map { "\($0)% · \(s.cycleCount) cycles" } ?? "--")])
            case .adapter:
                rows([("Rated", s.adapterWatts.map { "\($0) W" } ?? "--"),
                      ("Negotiated", [s.adapterVoltage.map { $0.formatted(.number.precision(.fractionLength(0))) + " V" },
                                      s.adapterCurrent.map { $0.formatted(.number.precision(.fractionLength(2))) + " A" }]
                                        .compactMap { $0 }.joined(separator: " · ")),
                      ("Drawing now", PowerFlowView.watts(flow.adapterIn)),
                      ("Into battery", PowerFlowView.watts(flow.adapterToBattery))])
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    // MARK: - Pieces

    @ViewBuilder private var appList: some View {
        if !energy.topApps.isEmpty {
            Text("Using power now").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 6) {
                let peak = max(energy.topApps.first?.watts ?? 1, 0.5)
                ForEach(energy.topApps.prefix(6)) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                        Text(app.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 6)
                        Capsule().fill(Theme.track).frame(width: 60, height: 5)
                            .overlay(alignment: .leading) {
                                Capsule().fill(tint.gradient).frame(width: 60 * min(app.watts / peak, 1), height: 5)
                            }
                        Text(app.watts.formatted(.number.precision(.fractionLength(app.watts < 1 ? 2 : 1))) + " W")
                            .font(.system(size: 11, weight: .semibold)).monospacedDigit().frame(width: 46, alignment: .trailing)
                    }
                }
            }
            .animation(.smooth(duration: 0.5), value: energy.topApps)
        }
    }

    private func rows(_ items: [(String, String)]) -> some View {
        VStack(spacing: 7) {
            ForEach(items.filter { !$0.1.isEmpty }, id: \.0) { item in
                HStack {
                    Text(item.0).font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text(item.1).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }
        }
    }

    private func percent(_ part: Double?, of whole: Double) -> String {
        guard let part, whole > 0 else { return "--" }
        return "\(Int((part / whole * 100).rounded()))%"
    }

    private var watts: Double? {
        switch node {
        case .adapter: flow.adapterIn
        case .batteryOut: flow.batteryToSystem
        case .batteryIn: flow.adapterToBattery
        case .mac: flow.systemLoad
        case .soc: flow.soc
        case .display: flow.display
        case .other: max(flow.systemLoad - (flow.soc ?? 0) - (flow.display ?? 0), 0)
        }
    }

    private var subtitle: String? {
        switch node {
        case .soc: "CPU + GPU + Neural Engine"
        case .display: NSScreen.main?.localizedName
        case .adapter: battery.snapshot.adapterName
        case .mac: Host.current().localizedName
        default: nil
        }
    }

    private var icon: String {
        switch node {
        case .adapter: "bolt.fill"
        case .batteryOut, .batteryIn: "battery.100percent"
        case .mac: "laptopcomputer"
        case .soc: "cpu"
        case .display: "display"
        case .other: "ellipsis.circle"
        }
    }

    private var tint: Color {
        switch node {
        case .adapter: Theme.bolt
        case .soc: Theme.soc
        case .display: Theme.displayAmber
        case .other: Theme.otherMint
        case .batteryIn: Theme.charging
        default: Theme.flowBlue
        }
    }
}

/// The Mac's chip, read once.
enum ChipInfo {
    static let name: String = sysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
    static let cores: String = {
        let p = sysctlInt("hw.perflevel0.physicalcpu"), e = sysctlInt("hw.perflevel1.physicalcpu")
        if let p, let e { return "\(p + e) CPU (\(p)P + \(e)E)" }
        return "\(ProcessInfo.processInfo.processorCount) CPU"
    }()
    static let memory: String = ByteCountFormatter.string(fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory)

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var v: Int32 = 0, size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
    }
}

/// Built-in display details: brightness (DisplayServices), resolution and refresh rate.
enum DisplayInfo {
    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private static let getBrightness: GetBrightness? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let f = dlsym(h, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(f, to: GetBrightness.self)
    }()

    @MainActor static func rows() -> [(String, String)] {
        let screen = NSScreen.screens.first { $0.localizedName.localizedCaseInsensitiveContains("built") } ?? NSScreen.main
        var out: [(String, String)] = []
        if let screen, let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 {
            var b: Float = 0
            if let getBrightness, getBrightness(id, &b) == 0 { out.append(("Brightness", "\(Int((b * 100).rounded()))%")) }
            let px = screen.frame.size.applying(.init(scaleX: screen.backingScaleFactor, y: screen.backingScaleFactor))
            out.append(("Resolution", "\(Int(px.width)) × \(Int(px.height))"))
            out.append(("Refresh rate", "\(screen.maximumFramesPerSecond) Hz"))
            out.append(("Displays connected", "\(NSScreen.screens.count)"))
        }
        out.append(("Tip", "Lower brightness is the biggest display saving"))
        return out
    }
}
