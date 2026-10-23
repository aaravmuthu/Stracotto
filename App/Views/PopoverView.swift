import SwiftUI

struct PopoverView: View {
    @Environment(BatteryMonitor.self) private var monitor
    @Environment(EnergyMonitor.self) private var energy
    @Environment(ChargeController.self) private var charge
    @Environment(\.showSettings) private var showSettings
    @AppStorage(Prefs.showPowerFlow) private var showPowerFlow = true
    @AppStorage(Prefs.showSpecs) private var showSpecs = true
    @AppStorage(Prefs.showEnergyApps) private var showEnergyApps = true
    @AppStorage(AppearancePrefs.showPowerMode) private var showPowerMode = true

    var body: some View {
        let s = monitor.snapshot
        @Bindable var charge = charge
        GlassEffectContainer(spacing: 2) {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // AlDente's Limit chip; on macOS 27 the hardware limit only takes 5% steps from 80, so it's a menu.
                Menu {
                    Picker("Charge Limit", selection: $charge.limit) {
                        ForEach(charge.allowedLimits.reversed(), id: \.self) { value in
                            Text(value == 100 ? "100% (Off)" : "\(value)%").tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 4) {
                        Text("Limit:").fontWeight(.bold)
                        Text("\(charge.target)%").monospacedDigit().contentTransition(.numericText(value: Double(charge.target)))
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .contentShape(.capsule)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .liquidGlass(tint: charge.isToppingUp ? Theme.charging.opacity(0.4) : nil, interactive: true, in: .capsule)
                .help("Battery stops charging at this level")
                Spacer()
                Button { charge.toggleTopUp() } label: {
                    HStack(spacing: 6) {
                        Text(charge.isToppingUp ? "Topping Up" : "Top Up")
                            .contentTransition(.interpolate)
                        Image(systemName: charge.isToppingUp ? "checkmark.circle.fill" : "plus.circle")
                            .font(.system(size: 19, weight: .regular))
                            .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp)))
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .frame(height: 30)
                }
                .buttonStyle(.plain)
                .liquidGlass(tint: charge.isToppingUp ? Theme.charging.opacity(0.55) : nil, interactive: true, in: .capsule)
                .help("Charge to 100% once, until you unplug")
                Button { showSettings() } label: {
                    Image(systemName: "square.grid.2x2").font(.system(size: 17)).frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .liquidGlass(interactive: true, in: .circle)
                .help("Open Dashboard")
            }
            .font(.system(size: 14))
            .padding(.bottom, 8)

            BatteryBar(percent: s.percent, state: s.state, plugEvents: monitor.plugEvents)

            if showPowerFlow {
                PowerFlowView(flow: s.flow, state: s.state, adapterWatts: s.adapterWatts, plugEvents: monitor.plugEvents, height: 181)
                    .padding(.top, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            if showPowerMode {
                PowerModeWidget(lowPower: s.lowPowerMode)
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            if showEnergyApps {
                EnergyAppsList(apps: energy.heavyApps)
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            if showSpecs {
                SpecsList(snapshot: s)
                    .padding(.top, 18)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 11)
        .frame(width: 388)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: charge.isToppingUp)
        .animation(Theme.spring, value: s.minutesRemaining == nil)
        .animation(Theme.spring, value: showPowerFlow)
        .animation(Theme.spring, value: showSpecs)
        .animation(Theme.spring, value: energy.heavyApps.isEmpty)
    }

    static func duration(_ minutes: Int) -> String { "\(minutes / 60):" + String(format: "%02d", minutes % 60) }
}

/// AlDente's power-mode widget: shows Low Power Mode and jumps to the Battery settings to change it.
struct PowerModeWidget: View {
    let lowPower: Bool

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension")!)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: lowPower ? "leaf.fill" : "bolt.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(lowPower ? Theme.bolt : Theme.charging)
                    .contentTransition(.symbolEffect(.replace))
                Text("Power Mode").font(.system(size: 13.5))
                Spacer()
                Text(lowPower ? "Low Power" : "Automatic")
                    .font(.system(size: 13.5, weight: .semibold))
                    .contentTransition(.interpolate)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 45)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .liquidGlass(tint: lowPower ? Theme.bolt.opacity(0.25) : nil, interactive: true, in: .capsule)
        .animation(.smooth(duration: 0.4), value: lowPower)
    }
}

/// Like the battery menu's "Using Significant Energy", with live watts. Rows slide and re-sort as load shifts.
struct EnergyAppsList: View {
    let apps: [EnergyMonitor.AppEnergy]

    var body: some View {
        if apps.isEmpty {
            Text("No Apps Using Significant Energy")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 45)
                .liquidGlass(in: .capsule)
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
                        if app.isApp {
                            Button { app.quit() } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 15)).foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Quit \(app.name)")
                        }
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
            row(Image(systemName: "stethoscope"), "Maximum Capacity:", "\(s.fullChargeCapacity) mAh", s.health.map { "\($0) %" })
            row(Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90"), "Cycle Count:", "\(s.cycleCount)")
            if showHardwarePercent { row(Image(systemName: "cpu"), "Hardware Percentage:", s.hardwarePercent.formatted(.number.precision(.fractionLength(1))) + " %") }
            divider
            row(Image(systemName: "flame"), "Battery Temperature:", s.temperature.map {
                Measurement(value: $0, unit: UnitTemperature.celsius)
                    .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(1))))
            } ?? "--")
            row(Image(systemName: "clock"), "Time Remaining:", s.minutesRemaining.map(Self.shortDuration) ?? "--")
            divider
            row(batteryLetter("i"), "Current:", s.amperage.formatted(.number.precision(.fractionLength(2))) + " A")
            row(batteryLetter("u"), "Voltage:", s.voltage.formatted(.number.precision(.fractionLength(0))) + " V")
            row(batteryLetter("p"), "Power:", (s.voltage * s.amperage).formatted(.number.precision(.fractionLength(2))) + " W")
            row(Image(systemName: "laptopcomputer"), "System Load:", s.flow.systemLoad.formatted(.number.precision(.fractionLength(2))) + " W")
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .liquidGlass(in: .rect(cornerRadius: 24, style: .continuous))
    }

    private var divider: some View {
        Rectangle().fill(.primary.opacity(0.15)).frame(height: 0.75).padding(.horizontal, 2).padding(.vertical, 8)
    }

    /// The vertical battery + boxed letter AlDente uses for current, voltage and power.
    private func batteryLetter(_ letter: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: "battery.100percent").rotationEffect(.degrees(-90)).font(.system(size: 11)).frame(width: 7)
            Image(systemName: "\(letter).square").font(.system(size: 12))
        }
    }

    private func row(_ icon: some View, _ title: String, _ value: String, _ extra: String? = nil) -> some View {
        HStack(spacing: 10) {
            icon.font(.system(size: 15)).frame(width: 26)
            Text(title).font(.system(size: 13.5))
            Spacer(minLength: 8)
            Text(value).font(.system(size: 13.5, weight: .semibold)).monospacedDigit().contentTransition(.numericText())
            if let extra {
                Text(extra).font(.system(size: 13.5, weight: .semibold)).monospacedDigit().frame(width: 58, alignment: .trailing)
            }
        }
        .frame(height: 25)
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
