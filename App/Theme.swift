import SwiftUI

enum Theme {
    /// Set by the snapshot renderer; see `liquidGlass`.
    nonisolated(unsafe) static var flatGlass = false

    // Sampled from AlDente's popover: charging green, holding blue, draining orange.
    static let charging = Color(red: 0.37, green: 0.67, blue: 0.39)
    static let paused = Color(red: 0.25, green: 0.53, blue: 0.91)
    static let draining = Color(red: 0.84, green: 0.57, blue: 0.24)
    static let bolt = Color(red: 0.98, green: 0.80, blue: 0.27)
    static let soc = Color(red: 0.69, green: 0.45, blue: 0.98)
    static let display = Color(red: 0.35, green: 0.78, blue: 0.98)
    /// Current AlDente fills a discharging battery in neutral glass-gray, not orange.
    static let discharging = Color(white: 0.62)

    /// Slab and backdrop greys sampled from AlDente's popover.
    static let slab = Color(red: 0.235, green: 0.235, blue: 0.24)
    static let backdrop = Color(red: 0.118, green: 0.118, blue: 0.122)
    static let chip = Color.primary.opacity(0.07)
    static let track = Color.primary.opacity(0.08)
    static let node = Color.primary.opacity(0.08)
    static let ribbon = Color.primary.opacity(0.10)

    static let chipRadius: CGFloat = 16
    static let nodeRadius: CGFloat = 13
    static let ribbonRadius: CGFloat = 7

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

    /// Every glass surface goes through here, so Reduce Transparency and offscreen snapshots get a solid stand-in
    /// with the same shape, rim and tint.
    func liquidGlass<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        modifier(LiquidGlass(shape: shape, tint: tint, interactive: interactive))
    }
}

private struct LiquidGlass<S: Shape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    @AppStorage(AppearancePrefs.liquidGlass) private var useLiquidGlass = false
    @AppStorage(AppearancePrefs.reduceTransparency) private var reduceTransparency = false

    func body(content: Content) -> some View {
        if useLiquidGlass && !reduceTransparency && !Theme.flatGlass {
            content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            // AlDente's slab: flat dark fill, a faint top sheen, and a rim that's brighter at the top.
            content.background {
                shape.fill(Theme.slab.mix(with: tint ?? .clear, by: tint == nil ? 0 : 0.55))
                    .overlay {
                        shape.fill(LinearGradient(colors: [.white.opacity(0.07), .clear], startPoint: .top, endPoint: .center))
                    }
                    .overlay {
                        shape.stroke(LinearGradient(colors: [.white.opacity(0.30), .white.opacity(0.10)], startPoint: .top, endPoint: .bottom),
                                     lineWidth: 1)
                    }
            }
        }
    }
}
