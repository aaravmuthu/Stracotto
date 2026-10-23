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
                    let ribbon = RibbonShape(top0: a.lowerBound, bottom0: a.upperBound, top1: b.lowerBound, bottom1: b.upperBound)
                    Color.clear
                        .overlay {
                            FlowStreaks(watts: link.watts).opacity(link.watts >= 0.01 ? 1 : 0).clipShape(ribbon)
                        }
                        .liquidGlass(tint: ribbonTint(for: link), in: ribbon)
                        .opacity(link.watts >= 0.01 ? 1 : 0)
                        .frame(width: ribbonWidth, height: size.height)
                        .offset(x: ribbonX[stage])
                }

                ForEach(Node.allCases, id: \.self) { node in
                    let span = layout.node(node)
                    let h = span.upperBound - span.lowerBound
                    nodeContent(node, height: h)
                        .frame(width: nodeWidth, height: max(h, 0))
                        .glassCard(radius: min(Theme.nodeRadius, max(h, 0) / 2))
                        .opacity(h > 1 ? 1 : 0)
                        .offset(x: columnX[node.column], y: span.lowerBound)
                }

                // Labels last, so a thin ribbon's label is never hidden behind the next ribbon.
                ForEach(links) { link in
                    let stage = link.from.column
                    let a = layout.end(link.id, source: true), b = layout.end(link.id, source: false)
                    // Thick ribbons carry their label inside; thin ones (SoC, display) hang it just under the band.
                    let thickness = min(a.upperBound - a.lowerBound, b.upperBound - b.lowerBound)
                    let thin = thickness < 22
                    let midY = (a.lowerBound + a.upperBound + b.lowerBound + b.upperBound) / 4
                    Text(Self.watts(link.watts))
                        .font(.system(size: thin ? 10 : 13.5, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: link.watts))
                        .fixedSize()
                        .opacity(link.watts >= 0.01 ? 1 : 0)
                        .position(x: ribbonX[stage] + ribbonWidth * 0.5, y: thin ? midY + thickness / 2 + 8 : midY)
                }
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.7), value: flow)
        .animation(.smooth(duration: 0.5), value: state)
    }

    static func watts(_ w: Double) -> String {
        guard w >= 0.01 else { return "" }
        return w.formatted(.number.precision(.fractionLength(w >= 10 ? 1 : 2))) + " W"
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

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let period = 3.2 / min(max(watts / 12, 0.6), 2.2)
            let phase = CGFloat((t / period).truncatingRemainder(dividingBy: 1))
            GeometryReader { p in
                ForEach(0..<2, id: \.self) { i in
                    let x = ((phase + CGFloat(i) * 0.5).truncatingRemainder(dividingBy: 1)) * 1.4 - 0.3
                    LinearGradient(colors: [.clear, .white.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
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

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(top0, bottom0), .init(top1, bottom1)) }
        set { (top0, bottom0, top1, bottom1) = (newValue.first.first, newValue.first.second, newValue.second.first, newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        // Corners round off where the ribbon meets a node; the radius shrinks for thin ribbons so ends stay pill-shaped.
        let r0 = min(Theme.ribbonRadius, max(bottom0 - top0, 0) / 2)
        let r1 = min(Theme.ribbonRadius, max(bottom1 - top1, 0) / 2)
        let (x0, x1, midX) = (rect.minX, rect.maxX, rect.midX)
        var p = Path()
        p.move(to: CGPoint(x: x0, y: top0 + r0))
        p.addQuadCurve(to: CGPoint(x: x0 + r0, y: top0), control: CGPoint(x: x0, y: top0))
        p.addCurve(to: CGPoint(x: x1 - r1, y: top1), control1: CGPoint(x: midX, y: top0), control2: CGPoint(x: midX, y: top1))
        p.addQuadCurve(to: CGPoint(x: x1, y: top1 + r1), control: CGPoint(x: x1, y: top1))
        p.addLine(to: CGPoint(x: x1, y: bottom1 - r1))
        p.addQuadCurve(to: CGPoint(x: x1 - r1, y: bottom1), control: CGPoint(x: x1, y: bottom1))
        p.addCurve(to: CGPoint(x: x0 + r0, y: bottom0), control1: CGPoint(x: midX, y: bottom1), control2: CGPoint(x: midX, y: bottom0))
        p.addQuadCurve(to: CGPoint(x: x0, y: bottom0 - r0), control: CGPoint(x: x0, y: bottom0))
        p.closeSubpath()
        return p
    }
}
