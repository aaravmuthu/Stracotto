import SwiftUI

/// Rounded fill showing charge, tinted by power state, with the status glyph riding inside the fill.
/// Plugging in plays a light sweep and a small bounce; while charging a soft gloss keeps travelling across the fill.
struct BatteryBar: View {
    let percent: Int
    let state: PowerState
    var plugEvents = 0
    var height: CGFloat = 25

    @State private var sweep: CGFloat = -0.6
    @State private var bounce: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let fill = max(proxy.size.width * CGFloat(percent) / 100, height)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.color(for: state).gradient)
                    .overlay { if state == .charging { ChargingGloss() } }
                    .overlay {
                        // One-shot plug-in sweep.
                        GeometryReader { p in
                            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: p.size.width * 0.45)
                                .offset(x: sweep * p.size.width)
                        }
                        .blendMode(.plusLighter)
                    }
                    .clipShape(.capsule)
                    .compositingGroup()
                    .frame(width: fill)
                    .scaleEffect(y: bounce, anchor: .center)
                    .overlay {
                        StatusGlyph(state: state, size: height * 0.62)
                            .foregroundStyle(.white)
                            .opacity(fill > height * 2.4 ? 1 : 0)
                    }
            }
        }
        .frame(height: height)
        .animation(Theme.spring, value: percent)
        .animation(.easeInOut(duration: 0.45), value: state)
        .onChange(of: plugEvents) { playPlugIn() }
        .accessibilityElement()
        .accessibilityLabel("Battery \(percent) percent, \(state.title)")
    }

    private func playPlugIn() {
        sweep = -0.6
        withAnimation(.easeInOut(duration: 0.9)) { sweep = 1.3 }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.5)) { bounce = 1.14 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.16)) { bounce = 1 }
    }
}

/// A slow, continuous highlight drifting left to right while the battery fills. Driven by the display clock, so it's
/// perfectly smooth and costs nothing once the popover closes.
private struct ChargingGloss: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t / 2.4).truncatingRemainder(dividingBy: 1))
            GeometryReader { p in
                LinearGradient(colors: [.clear, .white.opacity(0.22), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: p.size.width * 0.35)
                    .offset(x: (phase * 1.7 - 0.35) * p.size.width)
            }
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}
