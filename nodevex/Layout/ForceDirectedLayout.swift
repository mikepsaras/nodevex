import Foundation
import CoreGraphics

struct ForceDirectedLayout: LayoutStrategy {
    let name = "Force-directed"

    func compute(graph: GraphSnapshot) -> [UUID: CGPoint] {
        // TODO: proper Fruchterman-Reingold with category clustering and incremental
        // updates per ADR-0018, ADR-0019, ADR-0023. Placeholder distributes nodes
        // evenly around a circle so canvas rendering has distinct positions to draw.
        guard !graph.nodes.isEmpty else { return [:] }
        let n = CGFloat(graph.nodes.count)
        let radius = max(120, 24 * sqrt(n))
        var positions: [UUID: CGPoint] = [:]
        for (index, node) in graph.nodes.enumerated() {
            let angle = 2 * .pi * CGFloat(index) / n - .pi / 2
            positions[node.id] = CGPoint(
                x: cos(angle) * radius,
                y: sin(angle) * radius
            )
        }
        return positions
    }
}
