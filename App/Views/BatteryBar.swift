import SwiftUI

/// AlDente's charge bar: track, fill with the state glyph centred in it, the percentage just past the end of the
/// fill, the limit marker and (with Sailing Mode) a dashed floor. Read-only: the limit is chosen from the Limit chip.
///
/// Top Up: green stripes roll through the fill, a pulsing ghost fill reaches toward 100 %, and the marker glides to
/// 100 % with a green glow. Plug-in: halo bloom, light sweep and a small bounce.
struct BatteryBar: View {
    let percent: Int
    let state: PowerState
    var plugEvents = 0
    var height: CGFloat = 24
    var limit: Int? = nil
    var sailingFloor: Int? = nil
    var toppingUp = false

    @State private var sweep: CGFloat = -0.6
    @State private var bounce: CGFloat = 1
    @State private var glow: CGFloat = 0

    private var fillColor: Color {
        if toppingUp { return Theme.charging }
        switch state {
        case .charging: return Theme.charging
        case .paused: return Theme.paused
        case .pluggedDraining, .onBattery: return Color(white: 0.44)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = max(width * CGFloat(percent) / 100, height * 1.6)
            let labelInside = width - fill < 58
            let marker = toppingUp ? 100 : limit

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.clear)
                    .liquidGlass(in: Capsule(style: .continuous))

                // Ghost of where Top Up is heading, breathing between the fill and 100 %.
                if toppingUp {
                    TopUpGhost()
                        .frame(width: width, height: height)
                        .clipShape(.capsule(style: .continuous))
                        .transition(.opacity)
                }

                ZStack {
                    if toppingUp { TopUpStripes().transition(.opacity) }
                    else if state == .charging { ChargingGloss(color: Theme.charging) }
                    GeometryReader { p in
                        LinearGradient(colors: [.clear, Theme.charging.mix(with: .white, by: 0.45).opacity(0.85), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: p.size.width * 0.45)
                            .offset(x: sweep * p.size.width)
                    }
                    .blendMode(.plusLighter)
                    StatusGlyph(state: toppingUp ? .charging : state, size: height * 0.52)
                        .foregroundStyle(.white)
                        .opacity(fill > height * 2.2 ? 1 : 0)
                }
                .frame(width: fill, height: height)
                .background(Capsule(style: .continuous).fill(fillColor.gradient))
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                }
                .clipShape(.capsule(style: .continuous))
                .shadow(color: Theme.charging.opacity(0.9 * glow), radius: 14 * glow)
                .shadow(color: Theme.bolt.opacity(0.5 * glow), radius: 4 * glow)
                .scaleEffect(y: bounce)

                Text("\(percent)%")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                    .fixedSize()
                    .offset(x: labelInside ? fill - 50 : fill + 11)

                if let sailingFloor, !toppingUp {
                    Path { p in
                        let x = width * CGFloat(sailingFloor) / 100
                        p.move(to: CGPoint(x: x, y: 3)); p.addLine(to: CGPoint(x: x, y: height - 3))
                    }
                    .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3.5]))
                    .transition(.opacity)
                }

                if let marker {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(toppingUp ? Theme.charging.mix(with: .white, by: 0.35) : Color.white.opacity(0.62))
                        .frame(width: 6, height: height + 11)
                        .shadow(color: toppingUp ? Theme.charging.opacity(0.9) : .black.opacity(0.3), radius: toppingUp ? 6 : 2, y: toppingUp ? 0 : 1)
                        .offset(x: min(max(width * CGFloat(marker) / 100 - 3, 0), width - 6))
                }
            }
        }
        .frame(height: height)
        .padding(.vertical, 6)
        .animation(.smooth(duration: 0.6), value: percent)
        .animation(.smooth(duration: 0.45), value: state)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: toppingUp)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: limit)
        .onChange(of: plugEvents) { playPlugIn() }
        .onChange(of: toppingUp) { _, on in if on { playPlugIn() } }
        .accessibilityElement()
        .accessibilityLabel("Battery \(percent) percent, \(toppingUp ? "topping up to 100 percent" : state.title)")
    }

    private func playPlugIn() {
        glow = 0
        withAnimation(.smooth(duration: 0.3)) { glow = 1 }
        withAnimation(.smooth(duration: 1.2).delay(0.5)) { glow = 0 }
        sweep = -0.6
        withAnimation(.smooth(duration: 0.9)) { sweep = 1.3 }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.55)) { bounce = 1.12 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.16)) { bounce = 1 }
    }
}

/// A slow, continuous highlight drifting left to right while the battery fills.
private struct ChargingGloss: View {
    var color: Color = .white
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t / 2.4).truncatingRemainder(dividingBy: 1))
            GeometryReader { p in
                LinearGradient(colors: [.clear, color.mix(with: .white, by: 0.6).opacity(0.45), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: p.size.width * 0.35)
                    .offset(x: (phase * 1.7 - 0.35) * p.size.width)
            }
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}

/// Diagonal stripes rolling right through the fill while topping up — "filling past the limit".
private struct TopUpStripes: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let spacing: CGFloat = 14
                let shift = CGFloat((t * 22).truncatingRemainder(dividingBy: Double(spacing)))
                var x = -size.height - spacing + shift
                while x < size.width + spacing {
                    var stripe = Path()
                    stripe.move(to: CGPoint(x: x, y: size.height))
                    stripe.addLine(to: CGPoint(x: x + size.height, y: 0))
                    stripe.addLine(to: CGPoint(x: x + size.height + 6, y: 0))
                    stripe.addLine(to: CGPoint(x: x + 6, y: size.height))
                    stripe.closeSubpath()
                    ctx.fill(stripe, with: .color(.white.opacity(0.16)))
                    x += spacing
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// The unfilled part of the track gently breathing green, pointing at 100 %.
private struct TopUpGhost: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 2 * .pi / 1.8)
            LinearGradient(colors: [Theme.charging.opacity(0.10 + 0.18 * pulse), Theme.charging.opacity(0.04)],
                           startPoint: .leading, endPoint: .trailing)
        }
        .allowsHitTesting(false)
    }
}
