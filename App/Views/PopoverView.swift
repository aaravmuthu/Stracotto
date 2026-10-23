import SwiftUI

struct PopoverView: View {
    @Environment(BatteryMonitor.self) private var monitor
    @Environment(EnergyMonitor.self) private var energy
    @Environment(ChargeController.self) private var charge
    @Environment(\.showSettings) private var showSettings
    @AppStorage(Prefs.showPowerFlow) private var showPowerFlow = true
    @AppStorage(Prefs.showSpecs) private var showSpecs = true
    @AppStorage(Prefs.showEnergyApps) private var showEnergyApps = true
    @AppStorage(ChargePrefs.sailing) private var sailing = false
    @AppStorage(ChargePrefs.sailingRange) private var sailingRange = 5.0

    var body: some View {
        let s = monitor.snapshot
        @Bindable var charge = charge
        GlassEffectContainer(spacing: 10) {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Chip {
                    HStack(spacing: 4) {
                        Text("Limit:").fontWeight(.bold)
                        Text("\(charge.target)%").monospacedDigit().contentTransition(.numericText(value: Double(charge.target)))
                    }
                }
                .help(charge.backendStatus == .ready ? "Battery stops charging at this level" : "Charge control isn't active yet")
                Spacer()
                Button { charge.toggleTopUp() } label: {
                    HStack(spacing: 6) {
                        Text(charge.isToppingUp ? "Topping Up" : "Top Up")
                            .contentTransition(.interpolate)
                        Image(systemName: charge.isToppingUp ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 19, weight: .regular))
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                }
                .buttonStyle(.plain)
                .glassCard(radius: Theme.chipRadius, tint: charge.isToppingUp ? Theme.charging.opacity(0.55) : nil, interactive: true)
                .help("Charge to 100% once, until you unplug")
                Button { showSettings() } label: {
                    Image(systemName: "square.grid.2x2").font(.system(size: 17)).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .glassCard(radius: Theme.chipRadius, interactive: true)
                .help("Open Dashboard")
            }
            .font(.system(size: 14))

            BatteryBar(percent: s.percent, state: s.state, plugEvents: monitor.plugEvents,
                       limit: $charge.limit, limitLocked: charge.isToppingUp,
                       sailingFloor: sailing ? max(charge.limit - Int(sailingRange), ChargeController.limitRange.lowerBound) : nil)

            if showPowerFlow {
                PowerFlowView(flow: s.flow, state: s.state, adapterWatts: s.adapterWatts, plugEvents: monitor.plugEvents)
                    .padding(.top, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            if showEnergyApps {
                EnergyAppsList(apps: energy.heavyApps)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            if showSpecs {
                SpecsList(snapshot: s)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        }
        .padding(14)
        .frame(width: 360)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: charge.isToppingUp)
        .animation(Theme.spring, value: s.minutesRemaining == nil)
        .animation(Theme.spring, value: showPowerFlow)
        .animation(Theme.spring, value: showSpecs)
        .animation(Theme.spring, value: energy.heavyApps.isEmpty)
    }

    static func duration(_ minutes: Int) -> String { "\(minutes / 60):" + String(format: "%02d", minutes % 60) }
}

/// Like the battery menu's "Using Significant Energy", with live watts. Rows slide and re-sort as load shifts.
struct EnergyAppsList: View {
    let apps: [EnergyMonitor.AppEnergy]

    var body: some View {
        if apps.isEmpty {
            Text("No Apps Using Significant Energy")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassCard(radius: 22)
        } else {
            list
        }
    }

    private var list: some View {
        let peak = max(apps.first?.watts ?? 1, EnergyMonitor.hot)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Using Significant Energy", systemImage: "flame.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.multicolor)
            VStack(spacing: 6) {
                ForEach(apps) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                        Text(app.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 8)
                        GeometryReader { p in
                            Capsule().fill(Theme.track)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(app.watts >= EnergyMonitor.hot ? Theme.draining.gradient : Theme.paused.gradient)
                                        .frame(width: p.size.width * min(app.watts / peak, 1))
                                }
                        }
                        .frame(width: 70, height: 6)
                        Text(app.watts.formatted(.number.precision(.fractionLength(1))) + " W")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: app.watts))
                            .frame(width: 46, alignment: .trailing)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .glassCard(radius: 13)
                    .transition(.asymmetric(insertion: .scale(scale: 0.9).combined(with: .opacity), removal: .opacity))
                }
            }
        }
        .animation(Theme.spring, value: apps)
    }
}

/// Current AlDente's specifications card: one glass panel of label/value rows in three groups.
struct SpecsList: View {
    let snapshot: BatterySnapshot
    @AppStorage(Prefs.showHardwarePercent) private var showHardwarePercent = false

    var body: some View {
        let s = snapshot
        VStack(spacing: 0) {
            row("stethoscope", "Maximum Capacity:", "\(s.fullChargeCapacity) mAh", s.health.map { "\($0) %" })
            row("clock.arrow.circlepath", "Cycle Count:", "\(s.cycleCount)")
            if showHardwarePercent { row("cpu", "Hardware Percentage:", s.hardwarePercent.formatted(.number.precision(.fractionLength(1))) + " %") }
            Divider().padding(.vertical, 6)
            row("thermometer.medium", "Battery Temperature:", s.temperature.map {
                Measurement(value: $0, unit: UnitTemperature.celsius).formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
            } ?? "--")
            row("clock", "Time Remaining:", s.minutesRemaining.map(Self.shortDuration) ?? "--")
            Divider().padding(.vertical, 6)
            row("i.square", "Current:", s.amperage.formatted(.number.precision(.fractionLength(2))) + " A")
            row("v.square", "Voltage:", s.voltage.formatted(.number.precision(.fractionLength(s.voltage >= 10 ? 0 : 1))) + " V")
            row("p.square", "Power:", (s.voltage * s.amperage).formatted(.number.precision(.fractionLength(2))) + " W")
            row("laptopcomputer", "System Load:", s.flow.systemLoad.formatted(.number.precision(.fractionLength(2))) + " W")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(radius: 20)
    }

    private func row(_ icon: String, _ title: String, _ value: String, _ extra: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 20)
            Text(title).font(.system(size: 13))
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
            if let extra {
                Text(extra).font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 44, alignment: .trailing)
            }
        }
        .frame(height: 24)
        .animation(.smooth(duration: 0.5), value: value)
    }

    static func shortDuration(_ minutes: Int) -> String { minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m" }
}

/// AlDente's older "Specifications" widget: the numbers people actually check.
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
        .glassCard(radius: Theme.chipRadius)
        .animation(Theme.spring, value: value)
    }
}
