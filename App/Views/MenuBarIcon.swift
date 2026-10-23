import SwiftUI

/// The live menu bar item: percentage, an Apple-style battery that animates on plug/unplug, and a breathing flame
/// while some app is pulling hard. Hosted in an NSStatusItem so real SwiftUI animation runs in the menu bar.
struct MenuBarIcon: View {
    @Environment(BatteryMonitor.self) private var battery
    @Environment(EnergyMonitor.self) private var energy
    @AppStorage(Prefs.menuBarPercent) private var showPercent = true
    @AppStorage(Prefs.menuBarIcon) private var showIcon = true
    @AppStorage(Prefs.menuBarEnergyAlert) private var showEnergyAlert = true

    var body: some View {
        let s = battery.snapshot
        HStack(spacing: 5) {
            if showEnergyAlert && energy.isHot {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.draining)
                    .symbolEffect(.breathe.pulse.byLayer, options: .repeat(.continuous))
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
                    .help("\(energy.heavyApps.first?.name ?? "An app") is using a lot of energy")
            }
            if showPercent {
                Text("\(s.percent)%")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(s.percent)))
            }
            if showIcon || !showPercent {
                AppleBattery(percent: s.percent, state: s.state, plugEvents: battery.plugEvents)
            }
        }
        .fixedSize()
        .padding(.horizontal, 4)
        .animation(Theme.spring, value: s.percent)
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: energy.isHot)
        .animation(Theme.spring, value: showPercent)
    }
}

/// macOS-style battery glyph. The bolt and plug are knocked out of the fill like Apple's, so the menu bar shows through.
struct AppleBattery: View {
    let percent: Int
    let state: PowerState
    /// Increments on every plug-in; each bump replays the charge flash.
    let plugEvents: Int
    var width: CGFloat = 25
    var height: CGFloat = 12

    @State private var flash = false
    @State private var sweep: CGFloat = -1

    private var level: CGFloat { CGFloat(min(max(percent, 0), 100)) / 100 }
    private var isLow: Bool { percent <= 20 && state == .onBattery }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.6, style: .continuous)
                    .strokeBorder(.primary.opacity(0.45), lineWidth: 1)

                // Fill, with a light band that sweeps across it on plug-in.
                RoundedRectangle(cornerRadius: 1.8, style: .continuous)
                    .fill(fillColor)
                    .frame(width: max((width - 4) * level, 2))
                    .overlay {
                        GeometryReader { proxy in
                            LinearGradient(colors: [.clear, .white.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: proxy.size.width * 0.6)
                                .offset(x: sweep * proxy.size.width)
                        }
                        .clipShape(.rect(cornerRadius: 1.8))
                        .blendMode(.plusLighter)
                    }
                    .padding(2)

                ZStack {
                    glyph.scaleEffect(1.45).blendMode(.destinationOut)
                    glyph
                }
                .frame(width: width, height: height)
            }
            .frame(width: width, height: height)
            .compositingGroup()

            UnevenRoundedRectangle(cornerRadii: .init(bottomTrailing: 1.2, topTrailing: 1.2))
                .fill(.primary.opacity(0.45))
                .frame(width: 1.6, height: 4)
        }
        .animation(Theme.spring, value: percent)
        .animation(.easeInOut(duration: 0.4), value: isLow)
        .onChange(of: plugEvents) { replayFlash() }
    }

    private var fillColor: Color {
        if flash { return Theme.charging }
        return isLow ? .red : .primary
    }

    @ViewBuilder private var glyph: some View {
        Group {
            switch state {
            case .charging:
                Image(systemName: "bolt.fill").font(.system(size: 9, weight: .black))
                    .transition(.scale(scale: 0.1).combined(with: .opacity))
            case .paused, .pluggedDraining:
                Image(systemName: "powerplug.portrait.fill").font(.system(size: 8, weight: .black))
                    .transition(.scale(scale: 0.1).combined(with: .opacity))
            case .onBattery:
                EmptyView()
            }
        }
        .foregroundStyle(.primary)
        .animation(.spring(response: 0.38, dampingFraction: 0.52), value: state)
    }

    /// Green flash + light sweep, the menu bar's version of the iPhone plug-in moment.
    private func replayFlash() {
        sweep = -1
        withAnimation(.easeOut(duration: 0.18)) { flash = true }
        withAnimation(.easeInOut(duration: 0.75).delay(0.05)) { sweep = 1.4 }
        withAnimation(.easeInOut(duration: 0.6).delay(1.3)) { flash = false }
    }
}
