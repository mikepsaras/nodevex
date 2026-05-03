import Foundation
import CoreGraphics

struct ForceDirectedLayout: LayoutStrategy {
    let name = "Force-directed"

    func compute(graph: GraphSnapshot) -> [UUID: CGPoint] {
        // TODO: Fruchterman-Reingold or Barnes-Hut with category clustering force.
        Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, CGPoint.zero) })
    }
}
