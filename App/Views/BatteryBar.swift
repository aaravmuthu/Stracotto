import SwiftUI

/// Rounded fill showing charge, tinted by power state, with the status glyph riding inside the fill.
struct BatteryBar: View {
    let percent: Int
    let state: PowerState
    var height: CGFloat = 25

    var body: some View {
        GeometryReader { proxy in
            let fill = max(proxy.size.width * CGFloat(percent) / 100, height)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.color(for: state).gradient)
                    .frame(width: fill)
                    .overlay {
                        StatusGlyph(state: state, size: height * 0.62)
                            .foregroundStyle(.white)
                            .opacity(fill > height * 2.4 ? 1 : 0)
                    }
            }
        }
        .frame(height: height)
        .animation(Theme.spring, value: percent)
        .animation(.easeInOut(duration: 0.35), value: state)
        .accessibilityElement()
        .accessibilityLabel("Battery \(percent) percent, \(state.title)")
    }
}
