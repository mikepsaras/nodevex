import Foundation
import CoreGraphics

@MainActor
final class LayoutEngine {
    private(set) var positions: [UUID: CGPoint] = [:]
    var currentStrategy: any LayoutStrategy = ForceDirectedLayout()

    func relayout(graph: GraphSnapshot) {
        positions = currentStrategy.compute(graph: graph)
    }
}
