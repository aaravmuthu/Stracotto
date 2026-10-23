import SwiftUI

/// Sankey of power between charger, battery and system, in AlDente's three-column layout.
/// Every node and ribbon always exists; idle ones collapse to zero height, so state changes morph instead of cut.
struct PowerFlowView: View {
    let flow: PowerFlow
    let state: PowerState
    let adapterWatts: Int?
    var plugEvents = 0
    var height: CGFloat = 150

    private let nodeWidth: CGFloat = 50
    private let columnGap: CGFloat = 5
    private let nodeGap: CGFloat = 10
    private let minNode: CGFloat = 44

    enum Node: CaseIterable { case adapter, batteryOut, batteryIn, system }
    private struct Link: Identifiable { let id: Int; let from: Node; let to: Node; let watts: Double }

    private var links: [Link] {
        var l = [
            Link(id: 0, from: .adapter, to: .batteryIn, watts: flow.adapterToBattery),
            Link(id: 1, from: .adapter, to: .system, watts: flow.adapterToSystem),
            Link(id: 2, from: .batteryOut, to: .system, watts: flow.batteryToSystem),
        ]
        // Nothing measured yet: still show which way power is meant to go.
        if l.allSatisfy({ $0.watts < 0.01 }) {
            let i = state == .onBattery ? 2 : 1
            l[i] = Link(id: i, from: l[i].from, to: l[i].to, watts: 0.001)
        }
        return l
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = Layout(links: links, height: proxy.size.height, nodeGap: nodeGap, minNode: minNode)
            let ribbonX = nodeWidth + columnGap
            let ribbonWidth = proxy.size.width - 2 * ribbonX

            ZStack(alignment: .topLeading) {
                ForEach(links) { link in
                    let a = layout.linkSpan(link.id, atSource: true)
                    let b = layout.linkSpan(link.id, atSource: false)
                    let ribbon = RibbonShape(top0: a.lowerBound, bottom0: a.upperBound, top1: b.lowerBound, bottom1: b.upperBound)
                    ribbon
                        .fill(ribbonStyle(for: link))
                        .overlay {
                            FlowStreaks(watts: link.watts)
                                .opacity(link.watts >= 0.01 ? 1 : 0)
                                .clipShape(ribbon)
                        }
                        .compositingGroup()
                        .frame(width: ribbonWidth, height: proxy.size.height)
                        .offset(x: ribbonX)
                    Text(link.watts >= 0.01 ? link.watts.formatted(.number.precision(.fractionLength(2))) + " W" : "")
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: link.watts))
                        .opacity(min(a.upperBound - a.lowerBound, b.upperBound - b.lowerBound) >= 24 ? 1 : 0)
                        .frame(width: ribbonWidth)
                        .position(x: ribbonX + ribbonWidth / 2, y: (a.lowerBound + a.upperBound + b.lowerBound + b.upperBound) / 4)
                }

                ForEach(Node.allCases, id: \.self) { node in
                    let span = layout.nodeSpan(node)
                    nodeView(node, height: span.upperBound - span.lowerBound)
                        .frame(width: nodeWidth, height: max(span.upperBound - span.lowerBound, 0))
                        .background(Theme.node, in: .rect(cornerRadius: Theme.nodeRadius))
                        .clipShape(.rect(cornerRadius: Theme.nodeRadius))
                        .opacity(span.upperBound - span.lowerBound > 1 ? 1 : 0)
                        .offset(x: isLeft(node) ? 0 : proxy.size.width - nodeWidth, y: span.lowerBound)
                }
            }
        }
        .frame(height: height)
        .animation(Theme.spring, value: flow)
        .animation(Theme.spring, value: state)
    }

    private func isLeft(_ node: Node) -> Bool { node == .adapter || node == .batteryOut }

    private func ribbonStyle(for link: Link) -> AnyShapeStyle {
        // Blue wash toward the Mac whenever the battery is holding or helping, like AlDente.
        let tinted = state == .paused || state == .pluggedDraining
        guard tinted else { return AnyShapeStyle(Theme.ribbon) }
        let strength = link.from == .batteryOut ? 0.7 : 0.35
        return AnyShapeStyle(LinearGradient(colors: [Theme.ribbon, Theme.paused.opacity(strength)], startPoint: .leading, endPoint: .trailing))
    }

    @ViewBuilder private func nodeView(_ node: Node, height: CGFloat) -> some View {
        VStack(spacing: 6) {
            switch node {
            case .adapter:
                Image(systemName: "bolt.fill")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(state == .charging ? Theme.bolt : .primary)
                    .symbolEffect(.bounce.up.byLayer, value: plugEvents)
                if let adapterWatts, height > 80 { Text("\(adapterWatts)W").font(.system(size: 15)) }
            case .batteryOut:
                Image(systemName: "battery.100percent").font(.system(size: 20))
            case .batteryIn:
                Image(systemName: "battery.100percent.bolt").font(.system(size: 20))
            case .system:
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 20))
                    .foregroundStyle(state == .paused || state == .pluggedDraining ? Theme.paused : .primary)
                if height > 80, links.filter({ $0.to == .system && $0.watts >= 0.01 }).count > 1 {
                    Text("\(Int(flow.systemLoad.rounded()))W").font(.system(size: 15)).monospacedDigit()
                        .contentTransition(.numericText(value: flow.systemLoad))
                }
            }
        }
        .fixedSize()
    }

    /// Vertical spans for nodes and for each link's ends, proportional to watts.
    private struct Layout {
        private var nodes: [Node: ClosedRange<CGFloat>] = [:]
        private var sourceEnds: [Int: ClosedRange<CGFloat>] = [:]
        private var sinkEnds: [Int: ClosedRange<CGFloat>] = [:]

        init(links: [Link], height: CGFloat, nodeGap: CGFloat, minNode: CGFloat) {
            let weight = { (n: Node) in links.filter { $0.from == n || $0.to == n }.reduce(0) { $0 + $1.watts } }
            for column in [[Node.adapter, .batteryOut], [.batteryIn, .system]] {
                let active = column.filter { weight($0) > 0 }
                let total = active.reduce(0) { $0 + weight($1) }
                let free = height - nodeGap * CGFloat(max(active.count - 1, 0)) - minNode * CGFloat(active.count)
                var y: CGFloat = 0
                for node in column {
                    guard weight(node) > 0, total > 0 else { nodes[node] = y...y; continue }
                    let h = minNode + free * CGFloat(weight(node) / total)
                    nodes[node] = y...(y + h)
                    y += h + nodeGap
                }
            }
            // Links leave each source in the order their targets sit (top first) so ribbons never cross.
            for node in Node.allCases {
                guard let span = nodes[node] else { continue }
                let outgoing = links.filter { $0.from == node }, incoming = links.filter { $0.to == node }
                for (group, isSource) in [(outgoing, true), (incoming, false)] {
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

        func nodeSpan(_ node: Node) -> ClosedRange<CGFloat> { nodes[node] ?? 0...0 }
        func linkSpan(_ id: Int, atSource: Bool) -> ClosedRange<CGFloat> { (atSource ? sourceEnds[id] : sinkEnds[id]) ?? 0...0 }
    }
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
                    LinearGradient(colors: [.clear, .white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
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
        let midX = rect.midX
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: top0))
        p.addCurve(to: CGPoint(x: rect.maxX, y: top1), control1: CGPoint(x: midX, y: top0), control2: CGPoint(x: midX, y: top1))
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom1))
        p.addCurve(to: CGPoint(x: rect.minX, y: bottom0), control1: CGPoint(x: midX, y: bottom1), control2: CGPoint(x: midX, y: bottom0))
        p.closeSubpath()
        return p
    }
}
