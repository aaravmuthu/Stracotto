import AppKit
import SwiftUI

/// AlDente's limit slider: a glass track, a tinted glass fill with the state glyph centred in it, the percentage riding
/// just past the end of the fill, a dashed Sailing Mode floor and the limit handle.
struct BatteryBar: View {
    let percent: Int
    let state: PowerState
    var plugEvents = 0
    var height: CGFloat = 24
    /// nil hides the handle (read-only bar).
    var limit: Binding<Int>? = nil
    var limitLocked = false
    /// Values the limit may take; the handle snaps to the nearest.
    var allowedLimits: [Int] = Array(20...100)
    /// Sailing Mode's lower bound, drawn as a dashed tick.
    var sailingFloor: Int? = nil

    @State private var sweep: CGFloat = -0.6
    @State private var bounce: CGFloat = 1
    @State private var dragging = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let fill = max(width * CGFloat(percent) / 100, height * 1.6)
            let labelInside = width - fill < 56
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.clear)
                    .frame(height: height)
                    .liquidGlass(in: .capsule)

                ZStack {
                    if state == .charging { ChargingGloss() }
                    GeometryReader { p in
                        LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: p.size.width * 0.45)
                            .offset(x: sweep * p.size.width)
                    }
                    .blendMode(.plusLighter)
                    StatusGlyph(state: state, size: height * 0.52)
                        .foregroundStyle(.white)
                        .opacity(fill > height * 2.2 ? 1 : 0)
                }
                .clipShape(.capsule(style: .continuous))
                .frame(width: fill, height: height)
                .liquidGlass(tint: Theme.color(for: state).opacity(0.75), in: .capsule)
                .scaleEffect(y: bounce)

                Text("\(percent)%")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(percent)))
                    .fixedSize()
                    .offset(x: labelInside ? fill - 48 : fill + 11)

                if let sailingFloor, limit != nil {
                    Path { p in
                        let x = width * CGFloat(sailingFloor) / 100
                        p.move(to: CGPoint(x: x, y: 2)); p.addLine(to: CGPoint(x: x, y: height - 2))
                    }
                    .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2.5, 3]))
                    .transition(.opacity)
                }

                if let limit {
                    let x = width * CGFloat(limit.wrappedValue) / 100
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(.white.opacity(dragging ? 0.85 : 0.6))
                        .frame(width: 6, height: height + 11)
                        .shadow(color: .black.opacity(0.3), radius: dragging ? 5 : 2, y: 1)
                        .scaleEffect(dragging ? 1.1 : 1)
                        .offset(x: min(max(x - 3, 0), width - 6))
                        .opacity(limitLocked ? 0.4 : 1)
                }
            }
            .contentShape(.rect)
            .gesture(limit == nil || limitLocked ? nil : drag(width: width))
        }
        .frame(height: height)
        .padding(.vertical, 6) // room for the handle, which stands proud of the track
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
                let snapped = allowedLimits.min { abs($0 - raw) < abs($1 - raw) } ?? raw
                if snapped != limit.wrappedValue {
                    // A haptic tick on every step, like a detented slider.
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    limit.wrappedValue = snapped
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
                LinearGradient(colors: [.clear, .white.opacity(0.2), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: p.size.width * 0.35)
                    .offset(x: (phase * 1.7 - 0.35) * p.size.width)
            }
            .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
    }
}
