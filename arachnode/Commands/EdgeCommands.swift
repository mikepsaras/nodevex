import Foundation
import SwiftData

enum EdgeCommands {
    /// Inserts an edge. Returns nil for self-edges or duplicates of an
    /// existing (source, target) pair.
    @discardableResult
    static func createEdge(
        from sourceID: UUID,
        to targetID: UUID,
        strength: Double = 0.5,
        valence: EdgeValence = .neutral,
        in context: ModelContext
    ) -> Edge? {
        guard sourceID != targetID else { return nil }
        let descriptor = FetchDescriptor<Edge>(
            predicate: #Predicate { edge in
                edge.sourceID == sourceID && edge.targetID == targetID
            }
        )
        if let existing = try? context.fetch(descriptor), !existing.isEmpty {
            return nil
        }
        let edge = Edge(sourceID: sourceID, targetID: targetID, strength: strength, valence: valence)
        context.insert(edge)
        return edge
    }

    static func deleteEdge(_ edge: Edge, in context: ModelContext) {
        context.delete(edge)
    }
}
