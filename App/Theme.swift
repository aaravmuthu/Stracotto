import SwiftUI

enum Theme {
    /// Set by the snapshot renderer; see `liquidGlass`.
    nonisolated(unsafe) static var flatGlass = false

    // Sampled from AlDente's popover: charging green, holding blue, draining orange.
    static let charging = Color(red: 0.37, green: 0.67, blue: 0.39)
    static let paused = Color(red: 0.25, green: 0.53, blue: 0.91)
    static let draining = Color(red: 0.84, green: 0.57, blue: 0.24)
    static let bolt = Color(red: 0.98, green: 0.80, blue: 0.27)
    /// AlDente's text is a soft white, not pure white.
    static let text = Color(.sRGB, red: 225 / 255, green: 225 / 255, blue: 225 / 255)
    /// AlDente's flow blue, and the faint warm tone energy has as it leaves the battery.
    static let flowBlue = Color(.sRGB, red: 0.33, green: 0.55, blue: 0.86)
    static let batteryWarm = Color(.sRGB, red: 0.80, green: 0.56, blue: 0.40)
    static let displayAmber = Color(.sRGB, red: 0.86, green: 0.72, blue: 0.55)
    static let otherMint = Color(.sRGB, red: 0.56, green: 0.82, blue: 0.68)
    static let soc = Color(red: 0.69, green: 0.45, blue: 0.98)
    static let display = Color(red: 0.35, green: 0.78, blue: 0.98)
    /// Current AlDente fills a discharging battery in neutral glass-gray, not orange.
    static let discharging = Color(white: 0.62)

    /// Slab and backdrop greys sampled from AlDente's popover.
    static let slab = Color(.sRGB, red: 67 / 255, green: 67 / 255, blue: 67 / 255)       // flat interior, sampled raw
    static let backdrop = Color(.sRGB, red: 37 / 255, green: 37 / 255, blue: 37 / 255)   // popover background, sampled raw
    static let chip = Color.primary.opacity(0.07)
    static let track = Color.primary.opacity(0.08)
    static let node = Color.primary.opacity(0.08)
    static let ribbon = Color.primary.opacity(0.10)

    static let chipRadius: CGFloat = 16
    static let nodeRadius: CGFloat = 13
    static let ribbonRadius: CGFloat = 11

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
            // AlDente's slab, sampled from its popover at 2x: flat 84-grey fill; a bright hairline along the top and
            // bottom edges (~150) fading in over ~2 px, no bright sides; a dark halo (~42) separating it from the
            // 49-grey background.
            content.background {
                shape.fill(Theme.slab.mix(with: tint ?? .clear, by: tint == nil ? 0 : 0.55))
                    // Glass body: a soft sheen that fades from the top, darkening slightly toward the bottom.
                    .overlay {
                        shape.fill(LinearGradient(stops: [
                            .init(color: .white.opacity(0.07), location: 0),
                            .init(color: .white.opacity(0.015), location: 0.45),
                            .init(color: .black.opacity(0.04), location: 1),
                        ], startPoint: .top, endPoint: .bottom))
                    }
                    // Inner glow just inside the top and bottom rims (88 → 67 over a few px in AlDente).
                    .overlay {
                        GeometryReader { g in
                            let fade = min(8 / max(g.size.height, 1), 0.3)
                            shape.fill(LinearGradient(stops: [
                                .init(color: .white.opacity(0.13), location: 0),
                                .init(color: .clear, location: fade),
                                .init(color: .clear, location: 1 - fade),
                                .init(color: .white.opacity(0.12), location: 1),
                            ], startPoint: .top, endPoint: .bottom))
                        }
                    }
                    // Specular rim: bright along the top, lit along the bottom, barely there on the sides.
                    .overlay {
                        shape.stroke(LinearGradient(stops: [
                            .init(color: .white.opacity(0.48), location: 0),
                            .init(color: .white.opacity(0.06), location: 0.12),
                            .init(color: .white.opacity(0.06), location: 0.88),
                            .init(color: .white.opacity(0.38), location: 1),
                        ], startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
                    }
                    .shadow(color: .black.opacity(0.42), radius: 1.6)
            }
        }
    }
}
