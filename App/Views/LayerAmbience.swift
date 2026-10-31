import SwiftUI

/// Ambient motion that runs on Core Animation's render server instead of in SwiftUI. A SwiftUI `TimelineView` or
/// `repeatForever` animation re-renders the whole popover on the CPU every frame (about 10 % of a core while it's open);
/// these layers animate in the compositor and cost the app nothing once started. Same look, same timing.

/// A soft gradient band sliding across its container, looping forever.
struct SlidingBand: NSViewRepresentable {
    var colors: [Color]
    /// Band width as a fraction of the container's.
    var width: CGFloat
    /// Left edge at the start and end of a pass, as fractions of the container's width.
    var from: CGFloat
    var to: CGFloat
    var duration: Double
    /// Where in the loop to start, 0…1, so several bands can share one period.
    var phase: Double = 0
    var additive = false

    func makeNSView(context: Context) -> BandView { BandView() }
    func updateNSView(_ view: BandView, context: Context) { view.configure(self) }

    final class BandView: NSView {
        private let band = CAGradientLayer()
        private var spec: SlidingBand?
        private var laidOutWidth: CGFloat = 0

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = false
            band.startPoint = CGPoint(x: 0, y: 0.5)
            band.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.addSublayer(band)
        }
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(_ new: SlidingBand) {
            let changed = spec.map { $0.duration != new.duration || $0.from != new.from || $0.to != new.to || $0.width != new.width || $0.phase != new.phase } ?? true
            spec = new
            band.colors = new.colors.map { NSColor($0).cgColor }
            band.compositingFilter = new.additive ? CIFilter(name: "CIAdditionCompositing") : nil
            if changed { laidOutWidth = 0; needsLayout = true }
        }

        override func layout() {
            super.layout()
            guard let spec, bounds.width > 0, laidOutWidth != bounds.width else { return }
            laidOutWidth = bounds.width
            let w = bounds.width * spec.width
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            band.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
            band.position = CGPoint(x: bounds.width * spec.from + w / 2, y: bounds.height / 2)
            CATransaction.commit()
            let slide = CABasicAnimation(keyPath: "position.x")
            slide.fromValue = bounds.width * spec.from + w / 2
            slide.toValue = bounds.width * spec.to + w / 2
            slide.duration = spec.duration
            slide.timeOffset = spec.duration * spec.phase
            slide.repeatCount = .infinity
            slide.timingFunction = CAMediaTimingFunction(name: .linear)
            band.add(slide, forKey: "slide")
        }
    }
}

/// A layer whose opacity breathes between two values, looping forever.
struct BreathingGradient: NSViewRepresentable {
    var colors: [Color]
    var low: Float
    var high: Float
    var period: Double

    func makeNSView(context: Context) -> BreathView { BreathView() }
    func updateNSView(_ view: BreathView, context: Context) { view.configure(self) }

    final class BreathView: NSView {
        private let glow = CAGradientLayer()
        private var spec: BreathingGradient?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            glow.startPoint = CGPoint(x: 0, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 0.5)
            layer?.addSublayer(glow)
        }
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(_ new: BreathingGradient) {
            let changed = spec.map { $0.low != new.low || $0.high != new.high || $0.period != new.period } ?? true
            spec = new
            glow.colors = new.colors.map { NSColor($0).cgColor }
            if changed {
                glow.removeAnimation(forKey: "breathe")
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = new.low
                pulse.toValue = new.high
                pulse.duration = new.period / 2
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                glow.add(pulse, forKey: "breathe")
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            glow.frame = bounds
            CATransaction.commit()
        }
    }
}

/// Diagonal stripes rolling right, looping seamlessly after one stripe spacing.
struct RollingStripes: NSViewRepresentable {
    var spacing: CGFloat = 14
    var speed: CGFloat = 22   // pt per second
    var opacity: CGFloat = 0.16

    func makeNSView(context: Context) -> StripeView { StripeView() }
    func updateNSView(_ view: StripeView, context: Context) { view.spec = self; view.needsLayout = true }

    final class StripeView: NSView {
        var spec = RollingStripes()
        private let replicator = CAReplicatorLayer()
        private let stripe = CAShapeLayer()
        private var laidOut: CGSize = .zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            replicator.addSublayer(stripe)
            layer?.addSublayer(replicator)
        }
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            guard bounds.width > 0, bounds.height > 0, laidOut != bounds.size else { return }
            laidOut = bounds.size
            let h = bounds.height, s = spec.spacing
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            replicator.frame = bounds
            replicator.instanceCount = Int(ceil((bounds.width + h) / s)) + 3
            replicator.instanceTransform = CATransform3DMakeTranslation(s, 0, 0)
            stripe.frame = bounds
            // Slanted bar, bottom-left to top-right (AppKit's y axis points up, so this matches the flipped original).
            let path = CGMutablePath()
            let x = -h - s
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + h, y: h))
            path.addLine(to: CGPoint(x: x + h + 6, y: h))
            path.addLine(to: CGPoint(x: x + 6, y: 0))
            path.closeSubpath()
            stripe.path = path
            stripe.fillColor = NSColor.white.withAlphaComponent(spec.opacity).cgColor
            CATransaction.commit()
            replicator.removeAnimation(forKey: "roll")
            let roll = CABasicAnimation(keyPath: "transform.translation.x")
            roll.fromValue = 0
            roll.toValue = s
            roll.duration = Double(s / spec.speed)
            roll.repeatCount = .infinity
            roll.timingFunction = CAMediaTimingFunction(name: .linear)
            replicator.add(roll, forKey: "roll")
        }
    }
}

/// An image that swells and glows in a loop, run by the compositor. Stands in for an always-on SF Symbol effect, which
/// re-renders its host every frame; in the menu bar that cost about 6 % of a core for as long as an app stayed hot.
struct PulsingImage: NSViewRepresentable {
    var image: NSImage
    var period: Double = 1.4
    var scale: CGFloat = 1.14
    var dim: Float = 0.62

    func makeNSView(context: Context) -> PulseView { PulseView() }
    func updateNSView(_ view: PulseView, context: Context) { view.configure(self) }

    final class PulseView: NSView {
        private let content = CALayer()
        private var spec: PulsingImage?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            content.contentsGravity = .resizeAspect
            layer?.addSublayer(content)
        }
        required init?(coder: NSCoder) { nil }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        func configure(_ new: PulsingImage) {
            let restart = spec == nil
            spec = new
            content.contentsScale = window?.backingScaleFactor ?? 2
            content.contents = new.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            if restart {
                let swell = CABasicAnimation(keyPath: "transform.scale")
                swell.fromValue = 1
                swell.toValue = new.scale
                let glow = CABasicAnimation(keyPath: "opacity")
                glow.fromValue = new.dim
                glow.toValue = 1
                let group = CAAnimationGroup()
                group.animations = [swell, glow]
                group.duration = new.period / 2
                group.autoreverses = true
                group.repeatCount = .infinity
                group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                content.add(group, forKey: "pulse")
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            content.frame = bounds
            CATransaction.commit()
        }
    }
}
