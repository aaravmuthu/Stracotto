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

    @State private var selected: Node?
    @State private var selectedRect: CGRect = .zero

    enum Node: CaseIterable {
        case adapter, batteryOut, batteryIn, mac, soc, gpu, display, other
        var column: Int {
            switch self {
            case .adapter, .batteryOut: 0
            case .batteryIn, .mac: 1
            case .soc, .gpu, .display, .other: 2
            }
        }
    }
    fileprivate struct Link: Identifiable { let id: Int; let from: Node; let to: Node; let watts: Double }

    private let nodeWidth: CGFloat = 43
    private let gap: CGFloat = 6

    private var links: [Link] {
        let consumers = (flow.soc ?? 0) + (flow.gpu ?? 0) + (flow.display ?? 0)
        var l = [
            Link(id: 0, from: .adapter, to: .batteryIn, watts: flow.adapterToBattery),
            Link(id: 1, from: .adapter, to: .mac, watts: flow.adapterToSystem),
            Link(id: 2, from: .batteryOut, to: .mac, watts: flow.batteryToSystem),
            Link(id: 3, from: .mac, to: .soc, watts: flow.soc ?? 0),
            Link(id: 4, from: .mac, to: .gpu, watts: flow.gpu ?? 0),
            Link(id: 5, from: .mac, to: .display, watts: flow.display ?? 0),
            Link(id: 6, from: .mac, to: .other, watts: max(flow.systemLoad - consumers, 0)),
        ]
        // Nothing measured yet: still show which way power is meant to go.
        if l[0...2].allSatisfy({ $0.watts < 0.01 }) {
            let i = state == .onBattery ? 2 : 1
            l[i] = Link(id: i, from: l[i].from, to: l[i].to, watts: 0.001)
        }
        if l[3...6].allSatisfy({ $0.watts < 0.01 }) { l[6] = Link(id: 6, from: .mac, to: .other, watts: 0.001) }
        return l
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // node · ribbon · Mac · ribbons · consumers, each a separate glass slab 6 pt apart.
            let ribbonWidth = (size.width - nodeWidth * 3 - gap * 4) / 2
            let columnX: [CGFloat] = [0, nodeWidth + gap * 2 + ribbonWidth, size.width - nodeWidth]
            let ribbonX: [CGFloat] = [nodeWidth + gap, columnX[1] + nodeWidth + gap]
            let layout = SankeyLayout(links: links, height: size.height, idleBattery: batteryIdle)

            ZStack(alignment: .topLeading) {
                // Each stage's ribbons are unioned into one slab, so flows that share a node read as one shape that
                // peels into branches (dark wedges only where they separate), exactly like AlDente.
                ForEach(0..<2, id: \.self) { stage in
                    let stageLinks = links.filter { $0.from.column == stage }
                    let shape = StageShape(ribbons: stageLinks.map { link in
                        let a = layout.end(link.id, source: true), b = layout.end(link.id, source: false)
                        return link.watts >= 0.01 ? [a.lowerBound, a.upperBound, b.lowerBound, b.upperBound]
                            : [a.lowerBound, a.lowerBound, b.lowerBound, b.lowerBound]   // collapse in place, so it grows/shrinks smoothly
                    }, corners: stageLinks.map { link in
                        // Round only where the ribbon meets a node's outer edge; inner edges stay square so neighbours fuse.
                        let a = layout.end(link.id, source: true), b = layout.end(link.id, source: false)
                        let from = layout.node(link.from), to = layout.node(link.to)
                        return RibbonShape.Corners(top0: abs(a.lowerBound - from.lowerBound) < 0.5,
                                                   bottom0: abs(a.upperBound - from.upperBound) < 0.5,
                                                   top1: abs(b.lowerBound - to.lowerBound) < 0.5,
                                                   bottom1: abs(b.upperBound - to.upperBound) < 0.5)
                    })
                    Color.clear
                        .liquidGlass(in: shape)
                        .frame(width: ribbonWidth, height: size.height)
                        .offset(x: ribbonX[stage])
                    // AlDente's colour wash: energy turns blue as it reaches the Mac and fades out toward the consumers.
                    // While charging it flows (green/gold) instead of sitting still.
                    let totalWatts = stageLinks.reduce(0) { $0 + $1.watts }
                    StageGradient(stage: stage, palette: palette, watts: totalWatts)
                        .clipShape(shape)
                        .frame(width: ribbonWidth, height: size.height)
                        .offset(x: ribbonX[stage])
                        .allowsHitTesting(false)
                    // Each branch into a chip-side consumer takes on its own colour as it arrives.
                    if stage == 1 {
                        ForEach([(Node.soc, Theme.soc), (.gpu, Theme.gpu), (.display, Theme.displayAmber)], id: \.0) { node, color in
                            if let branch = stageLinks.first(where: { $0.to == node && $0.watts >= 0.01 }) {
                                let a = layout.end(branch.id, source: true), b = layout.end(branch.id, source: false)
                                LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: color.opacity(0.35), location: 0.7),
                                                       .init(color: color.opacity(0.6), location: 1)],
                                               startPoint: .leading, endPoint: .trailing)
                                    .clipShape(RibbonShape(top0: a.lowerBound, bottom0: a.upperBound, top1: b.lowerBound, bottom1: b.upperBound))
                                    .clipShape(shape)
                                    .frame(width: ribbonWidth, height: size.height)
                                    .offset(x: ribbonX[stage])
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }

                ForEach(Node.allCases, id: \.self) { node in
                    let span = layout.node(node)
                    let h = span.upperBound - span.lowerBound
                    // Glass ignores opacity, so idle nodes are removed rather than faded (else their icons ghost through).
                    if h > 1 {
                        nodeContent(node, height: h)
                            .frame(width: nodeWidth, height: h)
                            .liquidGlass(in: nodeShape(node, h))
                            .overlay {
                                if selected == node {
                                    nodeShape(node, h)
                                        .stroke(.white.opacity(0.55), lineWidth: 1.5)
                                }
                            }
                            .contentShape(nodeShape(node, h))
                            .onTapGesture {
                                selectedRect = CGRect(x: columnX[node.column], y: span.lowerBound, width: nodeWidth, height: h)
                                selected = node
                            }
                            .onHover { inside in if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() } }
                            .help(node.detailTitle)
                            .offset(x: columnX[node.column], y: span.lowerBound)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }

                // Labels last and laid out together: always on top, never overlapping, never outside the view.
                let labels = LabelLayout(links: links, layout: layout, width: ribbonWidth)
                ForEach(links) { link in
                    if let label = labels.position(link.id) {
                        Text(Self.watts(link.watts))
                            .font(.system(size: label.thin ? 11 : 12.5, weight: .semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText(value: link.watts))
                            .fixedSize()
                            .shadow(color: .black.opacity(0.7), radius: 2.5)
                            .shadow(color: .black.opacity(0.5), radius: 1)
                            .position(x: ribbonX[link.from.column] + label.x, y: label.y)
                            .transition(.opacity)
                    }
                }
            }
        }
        .popover(isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } }),
                 attachmentAnchor: .rect(.rect(selectedRect)), arrowEdge: .bottom) {
            if let selected { NodeDetailView(node: selected, flow: flow) }
        }
        .frame(height: height)
        // Readings land every 2 s; a slightly shorter glide keeps shapes in continuous motion instead of stop-start.
        .animation(.smooth(duration: 1.0), value: flow)
        .animation(.smooth(duration: 0.6), value: state)
    }

    /// Inner corners are tight; the corners on the diagram's outside edge are much rounder, as in AlDente.
    /// Plugged in, and the battery neither charging nor helping.
    private var batteryIdle: Bool {
        state != .onBattery && flow.batteryToSystem < 0.01 && flow.adapterToBattery < 0.01
    }

    private func nodeShape(_ node: Node, _ h: CGFloat) -> UnevenRoundedRectangle {
        let inner = min(10, h / 2.2), outer = min(24, h / 2.2)
        switch node.column {
        case 0: return UnevenRoundedRectangle(topLeadingRadius: outer, bottomLeadingRadius: outer, bottomTrailingRadius: inner, topTrailingRadius: inner, style: .continuous)
        case 2: return UnevenRoundedRectangle(topLeadingRadius: inner, bottomLeadingRadius: inner, bottomTrailingRadius: h > 60 ? outer : inner, topTrailingRadius: h > 60 ? outer : inner, style: .continuous)
        default: return UnevenRoundedRectangle(topLeadingRadius: inner, bottomLeadingRadius: inner, bottomTrailingRadius: inner, topTrailingRadius: inner, style: .continuous)
        }
    }

    static func watts(_ w: Double) -> String {
        guard w >= 0.01 else { return "" }
        return w.formatted(.number.precision(.fractionLength(w >= 10 ? 1 : 2))) + " W"
    }

    /// Each flow glows in the colour of what it carries: charger power yellow, charging green, battery help blue,
    /// SoC purple, display cyan; the rest stays white.
    private func streakColor(for link: Link) -> Color? {
        switch (link.from, link.to) {
        case (_, .batteryIn): Theme.charging
        case (.adapter, _): Theme.bolt
        case (.batteryOut, _): state == .pluggedDraining ? Theme.paused : nil
        default: nil
        }
    }

    /// Colours for the wash: where energy comes from, and what it becomes at the Mac.
    struct Palette: Equatable { let source: Color; let accent: Color }

    private var link0IsCharging: Bool { state == .charging }

    private var palette: Palette {
        switch state {
        case .charging: Palette(source: Theme.bolt.mix(with: Theme.charging, by: 0.3), accent: Theme.charging)
        case .pluggedDraining: Palette(source: Theme.bolt, accent: Theme.flowBlue)
        case .paused: Palette(source: Theme.bolt, accent: Theme.flowBlue)
        case .onBattery: Palette(source: Theme.batteryWarm, accent: Theme.flowBlue)
        }
    }

    private func stageTint(_ stage: Int) -> Color? {
        guard stage == 0 else { return nil }
        if state == .pluggedDraining { return Theme.paused.opacity(0.35) }
        if state == .charging { return Theme.charging.opacity(0.22) }
        return nil
    }

    private func ribbonTint(for link: Link) -> Color? {
        if link.from == .batteryOut && state == .pluggedDraining { return Theme.paused.opacity(0.45) }
        if link.to == .batteryIn { return Theme.charging.opacity(0.35) }
        return nil
    }

    @ViewBuilder private func nodeContent(_ node: Node, height: CGFloat) -> some View {
        let small = height < 30
        let iconSize: CGFloat = small ? 11 : 15
        VStack(spacing: 5) {
            switch node {
            case .adapter:
                Image(systemName: "bolt.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(state == .charging ? Theme.bolt : .primary)
                    .symbolEffect(.bounce.up.byLayer, value: plugEvents)
                if let adapterWatts, height > 80 { Text("\(adapterWatts)W").font(.system(size: 13)) }
            case .batteryOut:
                Image(systemName: "battery.100percent")
                    .font(.system(size: iconSize, weight: .light))
                    .foregroundStyle(Theme.text.opacity(batteryIdle ? 0.5 : 0.8))
                    .help(batteryIdle ? "Battery is resting: the charger is powering the Mac" : "Battery")
            case .batteryIn: Image(systemName: "battery.100percent.bolt").font(.system(size: iconSize))
            case .mac: Image(systemName: "laptopcomputer").font(.system(size: iconSize, weight: .light)).foregroundStyle(palette.accent.mix(with: .white, by: 0.35))
            case .soc: Image(systemName: "cpu").font(.system(size: iconSize)).foregroundStyle(Theme.soc)
            case .gpu: Image(systemName: "cube.transparent.fill").font(.system(size: iconSize)).foregroundStyle(Theme.gpu)
            case .display: FilledDisplayIcon(size: min(iconSize + 1, max((height - 5) / 0.8, 9)))
            case .other: Image(systemName: "ellipsis").font(.system(size: iconSize + 1, weight: .medium)).foregroundStyle(Theme.otherMint)
            }
        }
        .fixedSize()
    }
}

/// Where each watt label goes. Thick ribbons hold their label at the centre; thin ones hang it just under the band.
/// Labels in the same stage are then pushed apart so none overlap, and clamped inside the view.
private struct LabelLayout {
    struct Label { var x: CGFloat; var y: CGFloat; let thin: Bool }
    private var labels: [Int: Label] = [:]

    /// Every label sits inside its own branch. Thick bands hold it at the middle of the curve; thin branches hold it
    /// where they have fully peeled away (70 % along), centred on the band, so it never lands on a neighbour.
    init(links: [PowerFlowView.Link], layout: SankeyLayout, width: CGFloat) {
        for link in links where link.watts >= 0.01 {
            let a = layout.end(link.id, source: true), b = layout.end(link.id, source: false)
            let thickness = min(a.upperBound - a.lowerBound, b.upperBound - b.lowerBound)
            let thin = thickness < 30
            // Out of the Mac the branches only part company near the consumers, so their labels sit out there (the long
            // bottom branch is straight enough to keep its centred label); into the Mac they stay mid-curve.
            let u: CGFloat = link.from == .mac ? (link.to == .other ? 0.5 : 0.8) : (thin ? 0.72 : 0.5)
            func bez(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat) -> CGFloat {
                let m = 1 - u
                return m * m * m * p0 + 3 * m * m * u * p1 + 3 * m * u * u * p2 + u * u * u * p3
            }
            let x = bez(0, width / 2, width / 2, width)
            let top = bez(a.lowerBound, a.lowerBound, b.lowerBound, b.lowerBound)
            let bottom = bez(a.upperBound, a.upperBound, b.upperBound, b.upperBound)
            labels[link.id] = Label(x: x, y: (top + bottom) / 2, thin: thin)
        }
        // Branches leaving the Mac can still end up closer than a line of text; nudge them apart, top to bottom.
        var previous: CGFloat?
        for link in links where link.from == .mac && link.to != .other {
            guard var label = labels[link.id] else { continue }
            if let previous, label.y - previous < 14 { label.y = previous + 14 }
            labels[link.id] = label
            previous = label.y
        }
    }

    func position(_ id: Int) -> Label? { labels[id] }
}

/// Vertical spans for nodes and each link's two ends, proportional to watts.
private struct SankeyLayout {
    private var nodes: [PowerFlowView.Node: ClosedRange<CGFloat>] = [:]
    private var sourceEnds: [Int: ClosedRange<CGFloat>] = [:]
    private var sinkEnds: [Int: ClosedRange<CGFloat>] = [:]

    init(links: [PowerFlowView.Link], height: CGFloat, idleBattery: Bool = false) {
        func incoming(_ n: PowerFlowView.Node) -> Double { links.filter { $0.to == n }.reduce(0) { $0 + $1.watts } }
        func outgoing(_ n: PowerFlowView.Node) -> Double { links.filter { $0.from == n }.reduce(0) { $0 + $1.watts } }
        func weight(_ n: PowerFlowView.Node) -> Double { max(incoming(n), outgoing(n)) }

        // AlDente's geometry: a lone source or Mac node is ~70% tall and centred; two nodes in a column split the
        // full height; consumers are sized against the Mac node and spread top-to-bottom over the full height.
        let mainHeight = (height * 0.82).rounded()   // measured from AlDente: main nodes 82% tall, centred
        let nodeGap: CGFloat = 10
        for column in 0...2 {
            let members = PowerFlowView.Node.allCases.filter { $0.column == column }
            let active = members.filter { weight($0) > 0 }
            let total = active.reduce(0) { $0 + weight($1) }
            var heights: [PowerFlowView.Node: CGFloat] = [:]
            if column == 0, idleBattery, weight(.adapter) > 0, weight(.batteryOut) == 0 {
                // Plugged in but the battery is just sitting there: still show it, under the charger, as one block.
                let batteryH: CGFloat = 46
                let top = (height - mainHeight) / 2
                nodes[.adapter] = top...(top + mainHeight - batteryH - nodeGap)
                nodes[.batteryOut] = (top + mainHeight - batteryH)...(top + mainHeight)
                continue
            }
            if column < 2 {
                if active.count == 1 { heights[active[0]] = mainHeight }
                else if total > 0 {
                    let minH: CGFloat = 44
                    let free = height - nodeGap * CGFloat(active.count - 1) - minH * CGFloat(active.count)
                    for n in active { heights[n] = minH + max(free, 0) * CGFloat(weight(n) / total) }
                }
            } else if total > 0 {
                // AlDente's consumer column: the small consumers (CPU, display) stack from the top as slim bars, never
                // thinner than an icon; "everything else" takes the rest and sits on the bottom edge. This keeps the
                // branches in the same shape whatever the numbers are.
                let slim = [PowerFlowView.Node.soc, .gpu, .display].filter { weight($0) > 0 }
                // However many slim bars there are, leave "everything else" room at the bottom.
                let cap = slim.isEmpty ? 0 : (height - 34 - nodeGap * CGFloat(slim.count)) / CGFloat(slim.count)
                var y: CGFloat = 0
                for n in slim {
                    let h = min(max(20, mainHeight * CGFloat(weight(n) / total)), cap)
                    nodes[n] = y...(y + h)
                    y += h + nodeGap
                }
                if weight(.other) > 0 {
                    let wanted = mainHeight * CGFloat(weight(.other) / total)
                    let topLimit = slim.isEmpty ? (height - mainHeight) / 2 : y + nodeGap
                    let h = slim.isEmpty ? mainHeight : max(min(wanted, height - topLimit), 30)
                    nodes[.other] = (height - h - (slim.isEmpty ? (height - mainHeight) / 2 : 0))...(height - (slim.isEmpty ? (height - mainHeight) / 2 : 0))
                }
                for n in members where nodes[n] == nil { nodes[n] = 0...0 }
                continue
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
        // Two bands half a loop apart, sliding on the compositor; the speed still follows the watts.
        let period = 3.2 / min(max(watts / 12, 0.6), 2.2)
        let colors = [Color.clear, color.opacity(0.16), color.opacity(0.22), color.opacity(0.16), .clear]
        ZStack {
            SlidingBand(colors: colors, width: 0.55, from: -0.3, to: 1.1, duration: period, phase: 0, additive: true)
            SlidingBand(colors: colors, width: 0.55, from: -0.3, to: 1.1, duration: period, phase: 0.5, additive: true)
        }
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
        // Radius never exceeds half the band, so thin ribbons end in a neat pill rather than a bulb.
        func radius(_ thickness: CGFloat, _ on: Bool) -> CGFloat { on ? min(Theme.ribbonRadius, max(thickness, 0) / 2) : 0 }
        let rt0 = radius(bottom0 - top0, corners.top0), rb0 = radius(bottom0 - top0, corners.bottom0)
        let rt1 = radius(bottom1 - top1, corners.top1), rb1 = radius(bottom1 - top1, corners.bottom1)
        let (x0, x1) = (rect.minX, rect.maxX)
        // Classic Sankey: both control points at the horizontal midpoint, so a branch leaves its node flat, peels away
        // gradually and settles flat into the next node.
        let c0 = (x0 + x1) / 2, c1 = c0
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

/// All ribbons of one stage as a single unioned shape. Holds a fixed number of ribbons (3) so every edge animates.
struct StageShape: Shape {
    var edges: EdgeVector
    var corners: [RibbonShape.Corners]

    init(ribbons: [[CGFloat]], corners: [RibbonShape.Corners]) {
        edges = EdgeVector(values: ribbons.flatMap { $0 })
        self.corners = corners
    }

    var animatableData: EdgeVector {
        get { edges }
        set { edges = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var result = Path()
        let v = edges.values
        for i in stride(from: 0, to: v.count - 3, by: 4) {
            let (t0, b0, t1, b1) = (v[i], v[i + 1], v[i + 2], v[i + 3])
            guard b0 - t0 > 0.5 || b1 - t1 > 0.5 else { continue }
            // Inner edges overlap by a hair so neighbours fuse with no seam; outer corners round like AlDente's.
            let c = i / 4 < corners.count ? corners[i / 4] : RibbonShape.Corners()
            let ribbon = RibbonShape(top0: t0 - (c.top0 ? 0 : 0.5), bottom0: b0 + (c.bottom0 ? 0 : 0.5),
                                     top1: t1 - (c.top1 ? 0 : 0.5), bottom1: b1 + (c.bottom1 ? 0 : 0.5),
                                     corners: c).path(in: rect)
            result = result.isEmpty ? ribbon : result.union(ribbon)
        }
        return result
    }
}

/// A fixed-length list of edge positions that SwiftUI can interpolate.
struct EdgeVector: VectorArithmetic {
    var values: [CGFloat]

    static var zero: EdgeVector { EdgeVector(values: []) }

    private static func zip(_ a: EdgeVector, _ b: EdgeVector, _ f: (CGFloat, CGFloat) -> CGFloat) -> EdgeVector {
        let n = max(a.values.count, b.values.count)
        return EdgeVector(values: (0..<n).map { f($0 < a.values.count ? a.values[$0] : 0, $0 < b.values.count ? b.values[$0] : 0) })
    }
    static func + (a: EdgeVector, b: EdgeVector) -> EdgeVector { zip(a, b, +) }
    static func - (a: EdgeVector, b: EdgeVector) -> EdgeVector { zip(a, b, -) }
    mutating func scale(by rhs: Double) { values = values.map { $0 * CGFloat(rhs) } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + Double($1 * $1) } }
}

/// The colour wash over one stage's fused slab. Stage 0 (into the Mac) runs from a faint source tone to the accent at the
/// Mac; stage 1 (out of the Mac) starts in the accent and fades back to the slab grey toward the consumers.
/// It always flows: the colour breathes and a soft bright band rides along, faster the more power is moving.
private struct StageGradient: View {
    let stage: Int
    let palette: PowerFlowView.Palette
    let watts: Double

    /// Seconds for one wave to cross the stage. Fixed: tying it to live watts made the phase jump every time a new
    /// reading arrived, which read as stutter.
    private let period: Double = 1.6

    /// AlDente's static wash, as (colour, opacity, location).
    private var base: [(Color, Double, Double)] {
        let s = palette.source, a = palette.accent
        return stage == 0
            ? [(s, 0.10, 0), (s, 0.13, 0.45), (s, 0.10, 0.72), (a, 0.30, 0.9), (a, 0.55, 1)]
            : [(a, 0.62, 0), (a, 0.55, 0.3), (a.mix(with: Theme.otherMint, by: 0.45), 0.40, 0.55), (a, 0.10, 0.72), (a, 0.0, 0.82)]
    }

    /// The static wash, plus one soft band of the accent colour riding along it. The band is a single offset
    /// animation, so SwiftUI doesn't re-evaluate or re-rasterise the gradient every frame.
    var body: some View {
        ZStack {
            LinearGradient(stops: (0...24).map { i in
                let x = Double(i) / 24
                let (color, opacity) = sample(x)
                return .init(color: color.opacity(opacity), location: x)
            }, startPoint: .leading, endPoint: .trailing)
            SlidingBand(colors: [.clear, palette.accent.opacity(0.30), .clear], width: 0.7, from: -0.7, to: 1.0,
                        duration: period * 1.4, additive: true)
        }
    }

    private func sample(_ x: Double) -> (Color, Double) {
        let b = base
        guard let i = b.lastIndex(where: { $0.2 <= x }), i < b.count - 1 else { return (b.last!.0, b.last!.1) }
        let (c0, o0, l0) = b[i], (c1, o1, l1) = b[i + 1]
        let f = (x - l0) / max(l1 - l0, 0.0001)
        return (c0.mix(with: c1, by: f), o0 + (o1 - o0) * f)
    }
}

/// AlDente's display glyph: a filled amber screen on a small stand.
private struct FilledDisplayIcon: View {
    let size: CGFloat
    var body: some View {
        VStack(spacing: size * 0.06) {
            RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
                .fill(Theme.displayAmber.opacity(0.85))
                .overlay { RoundedRectangle(cornerRadius: size * 0.1, style: .continuous).stroke(Theme.displayAmber, lineWidth: max(size * 0.07, 1)) }
                .frame(width: size, height: size * 0.66)
            Capsule().fill(Theme.displayAmber).frame(width: size * 0.42, height: max(size * 0.07, 1))
        }
    }
}
