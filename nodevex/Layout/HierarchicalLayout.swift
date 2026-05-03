import Foundation
import CoreGraphics

struct HierarchicalLayout: LayoutStrategy {
    let name = "Hierarchical"

    func compute(graph: GraphSnapshot) -> [UUID: CGPoint] {
        // TODO: Sugiyama-style layered layout by causal depth.
        Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, CGPoint.zero) })
    }
}
