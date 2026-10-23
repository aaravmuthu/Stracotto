import AppKit
import SwiftUI

/// AlDente's limit slider: the fill shows charge (tinted by power state), the handle sets the limit.
/// Plugging in plays a light sweep and bounce; while charging a soft gloss keeps travelling across the fill.
struct BatteryBar: View {
    let percent: Int
    let state: PowerState
    var plugEvents = 0
    var height: CGFloat = 26
    /// nil hides the handle (read-only bar, e.g. the dashboard).
    var limit: Binding<Int>? = nil
    var limitLocked = false

    @State private var sweep: CGFloat = -0.6
    @State private var bounce: CGFloat = 1
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = max(width * CGFloat(percent) / 100, height)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(Theme.track)

                Capsule(style: .continuous)
                    .fill(Theme.color(for: state).gradient)
                    .overlay { if state == .charging { ChargingGloss() } }
                    .overlay {
                        GeometryReader { p in
                            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                                .frame(width: p.size.width * 0.45)
                                .offset(x: sweep * p.size.width)
                        }
                        .blendMode(.plusLighter)
                    }
                    .clipShape(.capsule(style: .continuous))
                    .compositingGroup()
                    .frame(width: fill)
                    .scaleEffect(y: bounce, anchor: .center)
                    .overlay {
                        StatusGlyph(state: state, size: height * 0.6)
                            .foregroundStyle(.white)
                            .opacity(fill > height * 2.4 ? 1 : 0)
                    }

                if let limit {
                    let x = width * CGFloat(limit.wrappedValue) / 100
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(.white.opacity(dragging ? 0.95 : 0.78))
                        .frame(width: 7, height: height + 12)
                        .shadow(color: .black.opacity(0.35), radius: dragging ? 6 : 3, y: 1)
                        .scaleEffect(dragging ? 1.12 : 1)
                        .offset(x: min(max(x - 3.5, 0), width - 7))
                        .opacity(limitLocked ? 0.45 : 1)
                }
            }
            .contentShape(.rect)
            .gesture(limit == nil || limitLocked ? nil : drag(width: width))
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.6), value: percent)
        .animation(.smooth(duration: 0.45), value: state)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: dragging)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: limit?.wrappedValue)
        .onChange(of: plugEvents) { playPlugIn() }
        .accessibilityElement()
        .accessibilityLabel("Battery \(percent) percent, \(state.title)")
        .accessibilityValue(limit.map { "Limit \($0.wrappedValue) percent" } ?? "")
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                dragging = true
                guard let limit else { return }
                let raw = Int((value.location.x / width * 100).rounded())
                let clamped = min(max(raw, ChargeController.limitRange.lowerBound), ChargeController.limitRange.upperBound)
                if clamped != limit.wrappedValue {
                    // A tick at the values people aim for.
                    if [50, 80, 100].contains(clamped) {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    var t = Transaction(); t.disablesAnimations = true
                    withTransaction(t) { limit.wrappedValue = clamped }
                }
            }
            .onEnded { _ in dragging = false }
    }

    private func playPlugIn() {
        sweep = -0.6
        withAnimation(.smooth(duration: 0.9)) { sweep = 1.3 }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.55)) { bounce = 1.12 }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.65).delay(0.16)) { bounce = 1 }
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
