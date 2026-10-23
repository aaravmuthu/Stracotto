import SwiftUI

/// The live menu bar item. Its width is fixed per configuration (never animated), so the status bar never
/// re-lays out mid-animation; that relayout was the main source of menu bar jank.
struct MenuBarIcon: View {
    @Environment(BatteryMonitor.self) private var battery
    @Environment(EnergyMonitor.self) private var energy
    @AppStorage(Prefs.menuBarEnergyAlert) private var showEnergyAlert = true
    @AppStorage(AppearancePrefs.iconStyle) private var iconStyle = MenuBarStyle.pot.rawValue
    @AppStorage(AppearancePrefs.stats) private var statsRaw = ""

    /// Width is a pure function of the configuration, never of animated content, so the status item never
    /// re-lays out mid-animation.
    static func width(style: MenuBarStyle, stats: Int, hot: Bool) -> CGFloat {
        style.width + 4 + CGFloat(stats) * (MenuBarStat.width + 4) + (hot ? 20 : 0)
    }

    var body: some View {
        let s = battery.snapshot
        let hot = showEnergyAlert && energy.isHot
        let style = MenuBarStyle(rawValue: iconStyle) ?? .pot
        let stats = MenuBarStat.parse(statsRaw)
        HStack(spacing: 4) {
            if hot {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LinearGradient(colors: [Theme.bolt, Theme.draining, .red], startPoint: .top, endPoint: .bottom))
                    .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.continuous))
                    .frame(width: 16)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                    .help("\(energy.heavyApps.first?.name ?? "An app") is using a lot of energy")
            }
            ForEach(stats) { stat in
                Text(stat.value(s))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(width: MenuBarStat.width)
            }
            MenuBarGlyph(style: style, percent: s.percent, state: s.state, plugEvents: battery.plugEvents)
        }
        .frame(width: Self.width(style: style, stats: stats.count, hot: hot), height: 22)
        .animation(.spring(response: 0.42, dampingFraction: 0.78), value: hot)
        .animation(.smooth(duration: 0.4), value: s.percent)
    }
}

/// The main icon in whichever style the user picked.
struct MenuBarGlyph: View {
    let style: MenuBarStyle
    let percent: Int
    let state: PowerState
    let plugEvents: Int

    var body: some View {
        switch style {
        case .pot:
            PotBattery(percent: percent, state: state, plugEvents: plugEvents)
        case .native:
            AppleBattery(percent: percent, state: state, plugEvents: plugEvents)
        case .status:
            HStack(spacing: 3) {
                Text("\(percent)%").font(.system(size: 12.5, weight: .medium)).monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                StatusGlyph(state: state, size: 12)
                    .foregroundStyle(state == .charging ? Theme.charging : .primary)
                    .symbolEffect(.bounce.up, value: plugEvents)
            }
            .frame(width: style.width)
        case .percentage:
            Text("\(percent)%").font(.system(size: 13, weight: .medium)).monospacedDigit()
                .contentTransition(.numericText(value: Double(percent)))
                .foregroundStyle(state == .charging ? Theme.charging : .primary)
                .frame(width: style.width)
        }
    }
}

/// Pill battery with the percentage inside, like the macOS 26/27 menu bar battery with "Show Percentage" on.
/// Digits and the bolt are knocked out of the fill so the menu bar shows through, exactly like Apple's.
struct AppleBattery: View {
    let percent: Int
    let state: PowerState
    /// Increments on every plug-in; each bump replays the charge flash.
    let plugEvents: Int

    static let size = CGSize(width: 31, height: 14)
    private let radius: CGFloat = 4.6

    @State private var flash = false
    @State private var sweep: CGFloat = -1

    private var level: CGFloat { CGFloat(min(max(percent, 0), 100)) / 100 }
    private var isLow: Bool { percent <= 20 && state == .onBattery }

    var body: some View {
        HStack(spacing: 1) {
            ZStack {
                // Empty part of the pill.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.primary.opacity(0.38))

                // Charged part, clipped to the pill so it keeps the rounded ends at any level.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(fillColor)
                            .frame(width: proxy.size.width * level)
                        LinearGradient(colors: [.clear, Theme.bolt.mix(with: .white, by: 0.4), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.55)
                            .offset(x: sweep * proxy.size.width)
                            .blendMode(.plusLighter)
                    }
                }
                .clipShape(.rect(cornerRadius: radius, style: .continuous))

                label.blendMode(.destinationOut)
            }
            .frame(width: Self.size.width - 2.5, height: Self.size.height)
            .compositingGroup()

            Capsule(style: .continuous)
                .fill(.primary.opacity(0.38))
                .frame(width: 1.5, height: 4.5)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(.smooth(duration: 0.6), value: percent)
        .animation(.smooth(duration: 0.45), value: isLow)
        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: state)
        .onChange(of: plugEvents) { replayFlash() }
        .accessibilityLabel("Battery \(percent) percent, \(state.title)")
    }

    private var label: some View {
        HStack(spacing: 0.5) {
            Text("\(percent)")
                .font(.system(size: percent == 100 ? 9.5 : 10.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(percent)))
            if let glyph {
                Image(systemName: glyph)
                    .font(.system(size: 8, weight: .black))
                    .transition(.asymmetric(insertion: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity),
                                            removal: .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)))
            }
        }
        .fixedSize()
    }

    private var glyph: String? {
        switch state {
        case .charging: "bolt.fill"
        case .paused, .pluggedDraining: "powerplug.portrait.fill"
        case .onBattery: nil
        }
    }

    private var fillColor: Color {
        if flash { return Theme.charging }
        return isLow ? .red : .primary
    }

    /// Green flash + light sweep on plug-in.
    private func replayFlash() {
        sweep = -1
        withAnimation(.smooth(duration: 0.25)) { flash = true }
        withAnimation(.smooth(duration: 0.85).delay(0.05)) { sweep = 1.5 }
        withAnimation(.smooth(duration: 0.7).delay(1.25)) { flash = false }
    }
}
