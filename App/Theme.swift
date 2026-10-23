import SwiftUI

enum Theme {
    /// Set by the snapshot renderer; see `liquidGlass`.
    nonisolated(unsafe) static var flatGlass = false

    // Sampled from AlDente's popover: charging green, holding blue, draining orange.
    static let charging = Color(red: 0.37, green: 0.67, blue: 0.39)
    static let paused = Color(red: 0.25, green: 0.53, blue: 0.91)
    static let draining = Color(red: 0.84, green: 0.57, blue: 0.24)
    static let bolt = Color(red: 0.98, green: 0.80, blue: 0.27)
    /// Current AlDente fills a discharging battery in neutral glass-gray, not orange.
    static let discharging = Color(white: 0.62)

    static let chip = Color.primary.opacity(0.07)
    static let track = Color.primary.opacity(0.08)
    static let node = Color.primary.opacity(0.08)
    static let ribbon = Color.primary.opacity(0.10)

    static let chipRadius: CGFloat = 16
    static let nodeRadius: CGFloat = 20
    static let ribbonRadius: CGFloat = 12

    /// One spring for everything so the bar, ribbons and numbers settle together.
    static let spring = Animation.spring(response: 0.55, dampingFraction: 0.82)

    static func color(for state: PowerState) -> Color {
        switch state {
        case .charging: charging
        case .paused: paused
        case .pluggedDraining, .onBattery: discharging
        }
    }
}

extension PowerState {
    /// Plug glyph plus a suffix, matching AlDente's live status icon.
    var suffixSymbol: String? {
        switch self {
        case .charging: "plus"
        case .paused: "pause.fill"
        case .pluggedDraining: "minus"
        case .onBattery: nil
        }
    }

    var title: String {
        switch self {
        case .charging: "Charging"
        case .paused: "Not Charging"
        case .pluggedDraining: "Charger Too Weak"
        case .onBattery: "On Battery"
        }
    }
}

/// The plug + state glyph used in the menu bar and inside the battery bar.
struct StatusGlyph: View {
    let state: PowerState
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: size * 0.12) {
            if let suffix = state.suffixSymbol {
                Image(systemName: "powerplug.portrait.fill")
                    .font(.system(size: size, weight: .semibold))
                Image(systemName: suffix)
                    .font(.system(size: size * 0.72, weight: .heavy))
                    .contentTransition(.symbolEffect(.replace.downUp))
            } else {
                // AlDente shows a bare dash while running on battery.
                Image(systemName: "minus")
                    .font(.system(size: size * 0.95, weight: .heavy))
            }
        }
    }
}

struct Chip<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(.horizontal, 14)
            .frame(height: 30)
            .liquidGlass(in: .capsule)
    }
}

extension View {
    /// Frosted Liquid Glass with Apple's continuous corners.
    func glassCard(radius: CGFloat, tint: Color? = nil, interactive: Bool = false) -> some View {
        liquidGlass(tint: tint, interactive: interactive, in: .rect(cornerRadius: radius, style: .continuous))
    }

    /// Every glass surface goes through here. Offscreen snapshots can't render glass, so they get a flat stand-in
    /// with the same shape, rim and tint.
    @ViewBuilder func liquidGlass<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        if Theme.flatGlass {
            background {
                shape.fill(Color(white: 0.30).mix(with: tint ?? .clear, by: tint == nil ? 0 : 0.6))
                    .overlay { shape.stroke(.white.opacity(0.22), lineWidth: 0.8) }
            }
        } else {
            glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        }
    }
}
