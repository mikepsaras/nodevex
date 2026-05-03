import Foundation
import SwiftData

enum NodeCommands {
    @discardableResult
    static func createNode(name: String, in context: ModelContext) -> Node {
        let node = Node(name: name)
        context.insert(node)
        return node
    }

    static func deleteNode(_ node: Node, in context: ModelContext) {
        context.delete(node)
    }
}
