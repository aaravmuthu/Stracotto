import SwiftUI

struct PopoverView: View {
    @Environment(BatteryMonitor.self) private var monitor
    @Environment(\.openSettings) private var openSettings
    @AppStorage(Prefs.showPowerFlow) private var showPowerFlow = true
    @AppStorage(Prefs.showSpecs) private var showSpecs = true

    var body: some View {
        let s = monitor.snapshot
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Chip {
                    HStack(spacing: 4) {
                        Text("Battery:").fontWeight(.bold)
                        Text("\(s.percent)%").monospacedDigit().contentTransition(.numericText(value: Double(s.percent)))
                    }
                }
                Spacer()
                if let minutes = s.minutesRemaining {
                    Chip {
                        Text(Self.duration(minutes) + (s.state == .charging ? " to full" : " left"))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(minutes)))
                    }
                    .transition(.blurReplace)
                }
                Button { openSettings(); NSApp.activate() } label: {
                    Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(Theme.chip, in: .rect(cornerRadius: Theme.chipRadius))
                .help("Settings")
            }
            .font(.system(size: 14))

            BatteryBar(percent: s.percent, state: s.state)

            if showPowerFlow {
                PowerFlowView(flow: s.flow, state: s.state, adapterWatts: s.adapterWatts)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            if showSpecs {
                SpecsGrid(snapshot: s)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(16)
        .frame(width: 380)
        .animation(Theme.spring, value: s.minutesRemaining == nil)
        .animation(Theme.spring, value: showPowerFlow)
        .animation(Theme.spring, value: showSpecs)
    }

    static func duration(_ minutes: Int) -> String { "\(minutes / 60):" + String(format: "%02d", minutes % 60) }
}

/// AlDente's "Specifications" widget: the numbers people actually check.
struct SpecsGrid: View {
    let snapshot: BatterySnapshot
    @AppStorage(Prefs.showHardwarePercent) private var showHardwarePercent = false

    var body: some View {
        let s = snapshot
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                SpecCell(icon: "heart.fill", title: "Health", value: s.health.map { "\($0)%" } ?? "--", detail: s.condition)
                SpecCell(icon: "arrow.triangle.2.circlepath", title: "Cycles", value: "\(s.cycleCount)", detail: "of \(s.designCycleCount)")
            }
            GridRow {
                SpecCell(icon: "thermometer.medium", title: "Temperature", value: s.temperature.map { $0.formatted(.number.precision(.fractionLength(1))) + "°C" } ?? "--", detail: nil)
                SpecCell(icon: "bolt.horizontal", title: "Power", value: s.voltage.formatted(.number.precision(.fractionLength(2))) + " V",
                         detail: s.amperage.formatted(.number.precision(.fractionLength(2))) + " A")
            }
            GridRow {
                SpecCell(icon: "battery.100percent", title: "Capacity", value: "\(s.fullChargeCapacity) mAh", detail: "design \(s.designCapacity)")
                SpecCell(icon: "cpu", title: "Hardware", value: showHardwarePercent ? s.hardwarePercent.formatted(.number.precision(.fractionLength(1))) + "%" : "\(s.remainingCapacity) mAh",
                         detail: showHardwarePercent ? "gauge reading" : "remaining")
            }
        }
    }
}

struct SpecCell: View {
    let icon: String, title: String, value: String, detail: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
                if let detail { Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(Theme.node, in: .rect(cornerRadius: Theme.chipRadius))
        .animation(Theme.spring, value: value)
    }
}
