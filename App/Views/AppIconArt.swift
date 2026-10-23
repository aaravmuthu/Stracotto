import SwiftUI

/// Stracotto's mark: a cast-iron braising pot whose body is a battery gauge, warmed by embers, with steam rising
/// into a charge bolt. Low-and-slow braise vs AlDente's quick pasta: warm and dark where AlDente is cool and light.
/// Drawn on a 1024 canvas; scales to any size.
struct AppIconArt: View {
    var level: CGFloat = 0.8

    private static let cream = Color(red: 0.96, green: 0.90, blue: 0.81)
    private static let ember = Color(red: 1.00, green: 0.55, blue: 0.18)
    private static let amber = Color(red: 1.00, green: 0.76, blue: 0.30)

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / 1024
            ZStack {
                // macOS icon tile: 824 pt squircle centred on the 1024 canvas.
                RoundedRectangle(cornerRadius: 185 * s, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.15, blue: 0.10), Color(red: 0.16, green: 0.05, blue: 0.04)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay {
                        RadialGradient(colors: [Self.ember.opacity(0.55), .clear], center: .init(x: 0.5, y: 0.92),
                                       startRadius: 0, endRadius: 420 * s)
                            .clipShape(.rect(cornerRadius: 185 * s, style: .continuous))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 185 * s, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 3 * s)
                    }
                    .frame(width: 824 * s, height: 824 * s)
                    .shadow(color: .black.opacity(0.35), radius: 18 * s, y: 10 * s)

                steam(s)
                pot(s)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func pot(_ s: CGFloat) -> some View {
        ZStack {
            // Side handles.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule()
                    .stroke(Self.cream, lineWidth: 26 * s)
                    .frame(width: 110 * s, height: 70 * s)
                    .offset(x: side * 262 * s, y: 70 * s)
            }
            // Body = battery case.
            RoundedRectangle(cornerRadius: 70 * s, style: .continuous)
                .fill(Self.cream)
                .frame(width: 470 * s, height: 300 * s)
                .offset(y: 110 * s)
            // Charge window inside the body.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 44 * s, style: .continuous)
                    .fill(Color(red: 0.24, green: 0.08, blue: 0.06))
                RoundedRectangle(cornerRadius: 44 * s, style: .continuous)
                    .fill(LinearGradient(colors: [Self.ember, Self.amber], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 390 * s * level)
                    .shadow(color: Self.ember.opacity(0.8), radius: 14 * s)
            }
            .frame(width: 390 * s, height: 190 * s)
            .offset(y: 110 * s)
            // Lid and knob.
            Capsule()
                .fill(Self.cream)
                .frame(width: 520 * s, height: 46 * s)
                .offset(y: -62 * s)
            Capsule()
                .fill(Self.cream)
                .frame(width: 110 * s, height: 44 * s)
                .offset(y: -102 * s)
        }
        .offset(y: 40 * s)
    }

    private func steam(_ s: CGFloat) -> some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 150))
                    p.addCurve(to: CGPoint(x: 0, y: 0), control1: CGPoint(x: -40, y: 100), control2: CGPoint(x: 40, y: 50))
                }
                .applying(CGAffineTransform(scaleX: s, y: s))
                .stroke(Self.cream.opacity(0.55), style: StrokeStyle(lineWidth: 22 * s, lineCap: .round))
                .frame(width: 1, height: 150 * s)
                .offset(x: side * 120 * s, y: -235 * s)
            }
            // The middle wisp becomes a bolt.
            Path { p in
                // Bolt in a 100 × 240 box (origin top-left), so it draws inside its own frame.
                let pts = [(70, 0), (8, 128), (52, 128), (24, 240), (96, 100), (52, 100), (70, 0)]
                for (i, pt) in pts.enumerated() {
                    let point = CGPoint(x: CGFloat(pt.0) * s, y: CGFloat(pt.1) * s)
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [Self.amber, Self.ember], startPoint: .top, endPoint: .bottom))
            .frame(width: 100 * s, height: 240 * s)
            .shadow(color: Self.ember.opacity(0.9), radius: 18 * s)
            .offset(y: -225 * s)
        }
    }
}
