import AppKit

// Draws the DMG window background at 1x and 2x. Usage: dmg-background <out-dir> [--notarized]
// Window is 660x400 pt; the app icon sits at (180, 190) and Applications at (480, 190), measured from the top-left.
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let notarized = CommandLine.arguments.contains("--notarized")
let size = NSSize(width: 660, height: 400)
let ember = NSColor(red: 1.0, green: 0.55, blue: 0.18, alpha: 1)

func render(scale: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale, pixelsHigh: Int(size.height) * scale,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let bounds = NSRect(origin: .zero, size: size)

    // Dark base with a warm glow rising behind the arrow and a green breath in the corner, like the welcome window.
    NSColor(srgbRed: 37 / 255, green: 37 / 255, blue: 37 / 255, alpha: 1).setFill(); bounds.fill()
    NSGradient(colors: [ember.withAlphaComponent(0.24), .clear])!
        .draw(fromCenter: NSPoint(x: 330, y: 400), radius: 0, toCenter: NSPoint(x: 330, y: 400), radius: 380, options: [])
    NSGradient(colors: [NSColor(srgbRed: 0.37, green: 0.67, blue: 0.39, alpha: 0.12), .clear])!
        .draw(fromCenter: NSPoint(x: 600, y: 0), radius: 0, toCenter: NSPoint(x: 600, y: 0), radius: 320, options: [])

    func text(_ s: String, size pt: CGFloat, weight: NSFont.Weight, alpha: CGFloat, y: CGFloat) {
        let para = NSMutableParagraphStyle(); para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: pt, weight: weight), .foregroundColor: NSColor.white.withAlphaComponent(alpha), .paragraphStyle: para,
        ]
        NSAttributedString(string: s, attributes: attrs).draw(in: NSRect(x: 0, y: y, width: size.width, height: pt * 1.5))
    }
    text("Drag Stracotto into Applications", size: 24, weight: .semibold, alpha: 0.95, y: 322)
    text("Then open it from your menu bar.", size: 13.5, weight: .regular, alpha: 0.55, y: 294)

    // A soft dashed arrow between the two icons (y measured from the bottom: 400 - 190 = 210).
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 262, y: 210))
    arrow.curve(to: NSPoint(x: 392, y: 210), controlPoint1: NSPoint(x: 297, y: 238), controlPoint2: NSPoint(x: 357, y: 238))
    arrow.lineWidth = 3.2
    arrow.lineCapStyle = .round
    arrow.setLineDash([1, 9], count: 2, phase: 0)
    ember.withAlphaComponent(0.9).setStroke()
    arrow.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 380, y: 224)); head.line(to: NSPoint(x: 398, y: 207)); head.line(to: NSPoint(x: 377, y: 197))
    head.lineWidth = 3.4; head.lineCapStyle = .round; head.lineJoinStyle = .round
    ember.setStroke(); head.stroke()

    // Finder always prints icon names in black, so each name sits on a pale plate to stay readable on the dark art.
    for x in [180.0, 480.0] {
        let plate = NSBezierPath(roundedRect: NSRect(x: x - 62, y: 116, width: 124, height: 24), xRadius: 12, yRadius: 12)
        NSColor.white.withAlphaComponent(0.86).setFill(); plate.fill()
    }

    if !notarized {
        text("First time: right-click Stracotto in Applications and choose Open.", size: 11.5, weight: .regular, alpha: 0.4, y: 26)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
try render(scale: 1).write(to: out.appendingPathComponent("background.png"))
try render(scale: 2).write(to: out.appendingPathComponent("background@2x.png"))
