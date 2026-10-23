import SwiftUI

/// AlDente's two-stage Power Flow: sources (charger, battery) → Mac (and battery when charging) → consumers
/// (SoC, display, everything else). Every node and ribbon always exists; idle ones collapse to zero height,
/// so state changes morph instead of cutting.
struct PowerFlowView: View {
    let flow: PowerFlow
    let state: PowerState
    let adapterWatts: Int?
    var plugEvents = 0
    var height: CGFloat = 170

    enum Node: CaseIterable {
        case adapter, batteryOut, batteryIn, mac, soc, display, other
        var column: Int {
            switch self {
            case .adapter, .batteryOut: 0
            case .batteryIn, .mac: 1
            case .soc, .display, .other: 2
            }
        }
    }
    fileprivate struct Link: Identifiable { let id: Int; let from: Node; let to: Node; let watts: Double }

    private let nodeWidth: CGFloat = 43
    private let gap: CGFloat = 6

    private var links: [Link] {
        let consumers = (flow.soc ?? 0) + (flow.display ?? 0)
        var l = [
            Link(id: 0, from: .adapter, to: .batteryIn, watts: flow.adapterToBattery),
            Link(id: 1, from: .adapter, to: .mac, watts: flow.adapterToSystem),
            Link(id: 2, from: .batteryOut, to: .mac, watts: flow.batteryToSystem),
            Link(id: 3, from: .mac, to: .soc, watts: flow.soc ?? 0),
            Link(id: 4, from: .mac, to: .display, watts: flow.display ?? 0),
            Link(id: 5, from: .mac, to: .other, watts: max(flow.systemLoad - consumers, 0)),
        ]
        // Nothing measured yet: still show which way power is meant to go.
        if l[0...2].allSatisfy({ $0.watts < 0.01 }) {
            let i = state == .onBattery ? 2 : 1
            l[i] = Link(id: i, from: l[i].from, to: l[i].to, watts: 0.001)
        }
        if l[3...5].allSatisfy({ $0.watts < 0.01 }) { l[5] = Link(id: 5, from: .mac, to: .other, watts: 0.001) }
        return l
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // node · ribbon · Mac · ribbons · consumers, each a separate glass slab 6 pt apart.
            let ribbonWidth = (size.width - nodeWidth * 3 - gap * 4) / 2
            let columnX: [CGFloat] = [0, nodeWidth + gap * 2 + ribbonWidth, size.width - nodeWidth]
            let ribbonX: [CGFloat] = [nodeWidth + gap, columnX[1] + nodeWidth + gap]
            let layout = SankeyLayout(links: links, height: size.height)

            ZStack(alignment: .topLeading) {
                ForEach(links) { link in
                    let stage = link.from.column
                    let a = layout.end(link.id, source: true), b = layout.end(link.id, source: false)
                    // Only corners on a node's outer edge round off; where two ribbons share a node they join flush, so a
                    // splitting flow reads as one smooth shape (as in AlDente) instead of notched pieces.
                    let from = layout.node(link.from), to = layout.node(link.to)
                    let ribbon = RibbonShape(top0: a.lowerBound, bottom0: a.upperBound, top1: b.lowerBound, bottom1: b.upperBound,
                                             corners: .init(top0: abs(a.lowerBound - from.lowerBound) < 0.5,
                                                            bottom0: abs(a.upperBound - from.upperBound) < 0.5,
                                                            top1: abs(b.lowerBound - to.lowerBound) < 0.5,
                                                            bottom1: abs(b.upperBound - to.upperBound) < 0.5))
                    // Glass content stays static; the moving streaks live in a separate layer above it, so the
                    // glass isn't recomposited every frame (that recompositing was the stutter).
                    if link.watts >= 0.01 {
                        Color.clear
                            .liquidGlass(tint: ribbonTint(for: link), in: ribbon)
                            .frame(width: ribbonWidth, height: size.height)
                            .offset(x: ribbonX[stage])
                            .transition(.opacity)
                        FlowStreaks(watts: link.watts, color: streakColor(for: link))
                            .clipShape(ribbon)
                            .frame(width: ribbonWidth, height: size.height)
                            .offset(x: ribbonX[stage])
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }

                ForEach(Node.allCases, id: \.self) { node in
                    let span = layout.node(node)
                    let h = span.upperBound - span.lowerBound
                    // Glass ignores opacity, so idle nodes are removed rather than faded (else their icons ghost through).
                    if h > 1 {
                        nodeContent(node, height: h)
                            .frame(width: nodeWidth, height: h)
                            .glassCard(radius: min(Theme.nodeRadius, h / 2))
                            .offset(x: columnX[node.column], y: span.lowerBound)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }

                // Labels last and laid out together: always on top, never overlapping, never outside the view.
                let labels = LabelLayout(links: links, layout: layout, height: size.height)
                ForEach(links) { link in
                    if let label = labels.position(link.id) {
                        Text(Self.watts(link.watts))
                            .font(.system(size: label.thin ? 10.5 : 13.5, weight: .bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: link.watts))
                            .fixedSize()
                            .padding(.horizontal, label.thin ? 6 : 0)
                            .padding(.vertical, label.thin ? 1.5 : 0)
                            .background { if label.thin { Capsule().fill(.black.opacity(0.45)) } }
                            .shadow(color: .black.opacity(0.35), radius: 2, y: 0.5)
                            .position(x: ribbonX[link.from.column] + ribbonWidth * 0.5, y: label.y)
                            .transition(.opacity)
                    }
                }
            }
        }
        .frame(height: height)
        // Readings land every 2 s; a slightly shorter glide keeps shapes in continuous motion instead of stop-start.
        .animation(.smooth(duration: 1.6), value: flow)
        .animation(.smooth(duration: 0.6), value: state)
    }

    static func watts(_ w: Double) -> String {
        guard w >= 0.01 else { return "" }
        return w.formatted(.number.precision(.fractionLength(w >= 10 ? 1 : 2))) + " W"
    }

    /// Each flow glows in the colour of what it carries: charger power yellow, charging green, battery help blue,
    /// SoC purple, display cyan; the rest stays white.
    private func streakColor(for link: Link) -> Color {
        switch (link.from, link.to) {
        case (_, .batteryIn): Theme.charging
        case (.adapter, _): Theme.bolt
        case (.batteryOut, _): state == .pluggedDraining ? Theme.paused : .white
        case (_, .soc): Theme.soc
        case (_, .display): Theme.display
        default: .white
        }
    }

    private func ribbonTint(for link: Link) -> Color? {
        if link.from == .batteryOut && state == .pluggedDraining { return Theme.paused.opacity(0.45) }
        if link.to == .batteryIn { return Theme.charging.opacity(0.35) }
        return nil
    }

    @ViewBuilder private func nodeContent(_ node: Node, height: CGFloat) -> some View {
        let small = height < 30
        let iconSize: CGFloat = small ? 11 : 18
        VStack(spacing: 5) {
            switch node {
            case .adapter:
                Image(systemName: "bolt.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(state == .charging ? Theme.bolt : .primary)
                    .symbolEffect(.bounce.up.byLayer, value: plugEvents)
                if let adapterWatts, height > 80 { Text("\(adapterWatts)W").font(.system(size: 13)) }
            case .batteryOut: Image(systemName: "battery.100percent").font(.system(size: iconSize))
            case .batteryIn: Image(systemName: "battery.100percent.bolt").font(.system(size: iconSize))
            case .mac: Image(systemName: "laptopcomputer").font(.system(size: iconSize))
            case .soc: Image(systemName: "cpu").font(.system(size: iconSize))
            case .display: Image(systemName: "display").font(.system(size: iconSize))
            case .other: Image(systemName: "ellipsis").font(.system(size: iconSize, weight: .bold))
            }
        }
        .fixedSize()
    }
}

/// Where each watt label goes. Thick ribbons hold their label at the centre; thin ones hang it just under the band.
/// Labels in the same stage are then pushed apart so none overlap, and clamped inside the view.
private struct LabelLayout {
    struct Label { var y: CGFloat; let thin: Bool }
    private var labels: [Int: Label] = [:]

    init(links: [PowerFlowView.Link], layout: SankeyLayout, height: CGFloat) {
        let minGap: CGFloat = 17
        for stage in 0...1 {
            var placed: [(id: Int, label: Label)] = links
                .filter { $0.from.column == stage && $0.watts >= 0.01 }
                .map { link in
                    let a = layout.end(link.id, source: true), b = layout.end(link.id, source: false)
                    let thickness = min(a.upperBound - a.lowerBound, b.upperBound - b.lowerBound)
                    let mid = (a.lowerBound + a.upperBound + b.lowerBound + b.upperBound) / 4
                    let thin = thickness < 24
                    return (link.id, Label(y: thin ? mid + thickness / 2 + 9 : mid, thin: thin))
                }
                .sorted { $0.label.y < $1.label.y }
            for i in placed.indices {
                placed[i].label.y = max(placed[i].label.y, 9)
                if i > 0 { placed[i].label.y = max(placed[i].label.y, placed[i - 1].label.y + minGap) }
            }
            // If the stack ran off the bottom, slide everything back up.
            if let last = placed.last, last.label.y > height - 9 {
                let shift = last.label.y - (height - 9)
                for i in placed.indices { placed[i].label.y -= shift }
            }
            for p in placed { labels[p.id] = p.label }
        }
    }

    func position(_ id: Int) -> Label? { labels[id] }
}

/// Vertical spans for nodes and each link's two ends, proportional to watts.
private struct SankeyLayout {
    private var nodes: [PowerFlowView.Node: ClosedRange<CGFloat>] = [:]
    private var sourceEnds: [Int: ClosedRange<CGFloat>] = [:]
    private var sinkEnds: [Int: ClosedRange<CGFloat>] = [:]

    init(links: [PowerFlowView.Link], height: CGFloat) {
        func incoming(_ n: PowerFlowView.Node) -> Double { links.filter { $0.to == n }.reduce(0) { $0 + $1.watts } }
        func outgoing(_ n: PowerFlowView.Node) -> Double { links.filter { $0.from == n }.reduce(0) { $0 + $1.watts } }
        func weight(_ n: PowerFlowView.Node) -> Double { max(incoming(n), outgoing(n)) }

        // AlDente's geometry: a lone source or Mac node is ~70% tall and centred; two nodes in a column split the
        // full height; consumers are sized against the Mac node and spread top-to-bottom over the full height.
        let mainHeight = (height * 0.69).rounded()
        let nodeGap: CGFloat = 10
        for column in 0...2 {
            let members = PowerFlowView.Node.allCases.filter { $0.column == column }
            let active = members.filter { weight($0) > 0 }
            let total = active.reduce(0) { $0 + weight($1) }
            var heights: [PowerFlowView.Node: CGFloat] = [:]
            if column < 2 {
                if active.count == 1 { heights[active[0]] = mainHeight }
                else if total > 0 {
                    let minH: CGFloat = 44
                    let free = height - nodeGap * CGFloat(active.count - 1) - minH * CGFloat(active.count)
                    for n in active { heights[n] = minH + max(free, 0) * CGFloat(weight(n) / total) }
                }
            } else if total > 0 {
                // Each consumer gets its share of the Mac node's height, but never thinner than an icon bar.
                for n in active { heights[n] = max(14, mainHeight * CGFloat(weight(n) / total)) }
            }
            let used = heights.values.reduce(0, +)
            let spacing = active.count > 1 ? (height - used) / CGFloat(active.count - 1) : 0
            var y = active.count == 1 ? (height - used) / 2 : 0
            for node in members {
                guard let h = heights[node] else { nodes[node] = y...y; continue }
                nodes[node] = y...(y + h)
                y += h + spacing
            }
        }
        // Each node's links stack top-to-bottom in the order their other ends sit, so ribbons never cross.
        for node in PowerFlowView.Node.allCases {
            guard let span = nodes[node] else { continue }
            for isSource in [true, false] {
                let group = links.filter { isSource ? $0.from == node : $0.to == node }
                let total = group.reduce(0) { $0 + $1.watts }
                var y = span.lowerBound
                for link in group {
                    let h = total > 0 ? (span.upperBound - span.lowerBound) * CGFloat(link.watts / total) : 0
                    if isSource { sourceEnds[link.id] = y...(y + h) } else { sinkEnds[link.id] = y...(y + h) }
                    y += h
                }
            }
        }
    }

    func node(_ n: PowerFlowView.Node) -> ClosedRange<CGFloat> { nodes[n] ?? 0...0 }
    func end(_ id: Int, source: Bool) -> ClosedRange<CGFloat> { (source ? sourceEnds[id] : sinkEnds[id]) ?? 0...0 }
}

/// Soft light bands drifting left to right through a ribbon, so you can see power moving.
/// Speed follows watts, capped so a 90 W charger doesn't strobe.
private struct FlowStreaks: View {
    let watts: Double
    var color: Color = .white

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period = 3.2 / min(max(watts / 12, 0.6), 2.2)
            let phase = CGFloat((t / period).truncatingRemainder(dividingBy: 1))
            GeometryReader { p in
                ForEach(0..<2, id: \.self) { i in
                    let x = ((phase + CGFloat(i) * 0.5).truncatingRemainder(dividingBy: 1)) * 1.4 - 0.3
                    LinearGradient(colors: [.clear, color.opacity(color == .white ? 0.09 : 0.32), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: p.size.width * 0.3)
                        .offset(x: x * p.size.width)
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

/// A band whose two ends can sit at different heights, joined by S-curves. All four edges animate.
struct RibbonShape: Shape {
    var top0: CGFloat, bottom0: CGFloat, top1: CGFloat, bottom1: CGFloat
    var corners = Corners()

    struct Corners { var top0 = true, bottom0 = true, top1 = true, bottom1 = true }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(top0, bottom0), .init(top1, bottom1)) }
        set { (top0, bottom0, top1, bottom1) = (newValue.first.first, newValue.first.second, newValue.second.first, newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        // Radius never exceeds a third of the band, so thin ribbons keep straight sides instead of turning into bulbs.
        func radius(_ thickness: CGFloat, _ on: Bool) -> CGFloat { on ? min(Theme.ribbonRadius, max(thickness, 0) / 3) : 0 }
        let rt0 = radius(bottom0 - top0, corners.top0), rb0 = radius(bottom0 - top0, corners.bottom0)
        let rt1 = radius(bottom1 - top1, corners.top1), rb1 = radius(bottom1 - top1, corners.bottom1)
        let (x0, x1) = (rect.minX, rect.maxX)
        // Control points at 45% / 55% give a long, even S-curve with horizontal tangents at both ends.
        let c0 = x0 + (x1 - x0) * 0.45, c1 = x0 + (x1 - x0) * 0.55
        var p = Path()
        p.move(to: CGPoint(x: x0, y: top0 + rt0))
        p.addQuadCurve(to: CGPoint(x: x0 + rt0, y: top0), control: CGPoint(x: x0, y: top0))
        p.addCurve(to: CGPoint(x: x1 - rt1, y: top1), control1: CGPoint(x: c0, y: top0), control2: CGPoint(x: c1, y: top1))
        p.addQuadCurve(to: CGPoint(x: x1, y: top1 + rt1), control: CGPoint(x: x1, y: top1))
        p.addLine(to: CGPoint(x: x1, y: bottom1 - rb1))
        p.addQuadCurve(to: CGPoint(x: x1 - rb1, y: bottom1), control: CGPoint(x: x1, y: bottom1))
        p.addCurve(to: CGPoint(x: x0 + rb0, y: bottom0), control1: CGPoint(x: c1, y: bottom1), control2: CGPoint(x: c0, y: bottom0))
        p.addQuadCurve(to: CGPoint(x: x0, y: bottom0 - rb0), control: CGPoint(x: x0, y: bottom0))
        p.closeSubpath()
        return p
    }
}
