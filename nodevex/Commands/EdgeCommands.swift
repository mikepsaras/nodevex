import Foundation
import SwiftData

enum EdgeCommands {
    @discardableResult
    static func createEdge(
        from sourceID: UUID,
        to targetID: UUID,
        strength: Double = 0.5,
        valence: EdgeValence = .neutral,
        in context: ModelContext
    ) -> Edge {
        let edge = Edge(sourceID: sourceID, targetID: targetID, strength: strength, valence: valence)
        context.insert(edge)
        return edge
    }

    static func deleteEdge(_ edge: Edge, in context: ModelContext) {
        context.delete(edge)
    }
}
