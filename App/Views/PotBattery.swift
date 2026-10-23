import SwiftUI

/// Stracotto's own menu bar battery, a tiny version of the app icon: a braising pot whose body is the charge gauge.
/// The percentage is knocked out of the fill like Apple's; when charging the lid knob becomes a bolt rising like steam.
struct PotBattery: View {
    let percent: Int
    let state: PowerState
    /// Increments on every plug-in; each bump replays the charge flash.
    let plugEvents: Int

    static let size = CGSize(width: 34, height: 18)

    @State private var flash = false
    @State private var sweep: CGFloat = -1

    private var level: CGFloat { CGFloat(min(max(percent, 0), 100)) / 100 }
    private var isLow: Bool { percent <= 20 && state == .onBattery }
    private var charging: Bool { state == .charging }

    private let pot = CGSize(width: 24, height: 11.5)
    private let bodyRadius: CGFloat = 3.8

    var body: some View {
        ZStack {
            // Handles.
            HStack(spacing: pot.width + 1) {
                Capsule(style: .continuous).fill(.primary.opacity(0.45)).frame(width: 3, height: 4.5)
                Capsule(style: .continuous).fill(.primary.opacity(0.45)).frame(width: 3, height: 4.5)
            }
            .offset(y: 3.2)

            // Body = gauge, with the number knocked out.
            ZStack {
                RoundedRectangle(cornerRadius: bodyRadius, style: .continuous).fill(.primary.opacity(0.38))
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(fillColor).frame(width: proxy.size.width * level)
                        LinearGradient(colors: [.clear, Theme.bolt.mix(with: .white, by: 0.4), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.55)
                            .offset(x: sweep * proxy.size.width)
                            .blendMode(.plusLighter)
                    }
                }
                .clipShape(.rect(cornerRadius: bodyRadius, style: .continuous))
                Text("\(percent)")
                    .font(.system(size: percent == 100 ? 8.5 : 9.5, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                    .blendMode(.destinationOut)
            }
            .frame(width: pot.width, height: pot.height)
            .compositingGroup()
            .offset(y: 3.2)

            // Lid.
            Capsule(style: .continuous)
                .fill(.primary)
                .frame(width: pot.width + 4, height: 2.2)
                .offset(y: -4.3)

            // Knob, or a bolt rising out of the pot while charging.
            ZStack {
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundStyle(flash ? Theme.charging : .primary)
                        .transition(.asymmetric(insertion: .scale(scale: 0.2, anchor: .bottom).combined(with: .offset(y: 3)).combined(with: .opacity),
                                                removal: .scale(scale: 0.2, anchor: .bottom).combined(with: .opacity)))
                } else {
                    Capsule(style: .continuous)
                        .fill(.primary)
                        .frame(width: 6, height: 2)
                        .offset(y: 2)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .offset(y: -7.4)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .animation(.smooth(duration: 0.6), value: percent)
        .animation(.smooth(duration: 0.45), value: isLow)
        .animation(.spring(response: 0.42, dampingFraction: 0.62), value: charging)
        .onChange(of: plugEvents) { replayFlash() }
        .accessibilityLabel("Battery \(percent) percent, \(state.title)")
    }

    private var fillColor: Color {
        if flash { return Theme.charging }
        return isLow ? .red : .primary
    }

    private func replayFlash() {
        sweep = -1
        withAnimation(.smooth(duration: 0.25)) { flash = true }
        withAnimation(.smooth(duration: 0.85).delay(0.05)) { sweep = 1.5 }
        withAnimation(.smooth(duration: 0.7).delay(1.25)) { flash = false }
    }
}
