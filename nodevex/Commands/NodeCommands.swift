import Foundation
import SwiftData
import CoreGraphics

enum NodeCommands {
    @discardableResult
    static func createNode(name: String, in context: ModelContext) -> Node {
        let node = Node(name: name)
        context.insert(node)
        return node
    }

    /// Deletes a node and cascade-deletes any edges that reference it as source
    /// or target. Edge endpoints are stored as UUIDs (not @Relationship), so we
    /// have to fetch and delete related edges manually here.
    static func deleteNode(_ node: Node, in context: ModelContext) {
        let nodeID = node.id
        let descriptor = FetchDescriptor<Edge>(
            predicate: #Predicate { edge in
                edge.sourceID == nodeID || edge.targetID == nodeID
            }
        )
        if let relatedEdges = try? context.fetch(descriptor) {
            for edge in relatedEdges {
                context.delete(edge)
            }
        }
        context.delete(node)
    }

    static func pinNode(_ node: Node, at position: CGPoint) {
        node.isPinned = true
        node.pinnedX = Double(position.x)
        node.pinnedY = Double(position.y)
    }

    static func unpinNode(_ node: Node) {
        node.isPinned = false
        node.pinnedX = nil
        node.pinnedY = nil
    }
}
