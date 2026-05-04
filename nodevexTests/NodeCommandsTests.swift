import Testing
import SwiftData
@testable import nodevex

@Suite("NodeCommands")
@MainActor
struct NodeCommandsTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Node.self, Edge.self, Category.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test("createNode inserts a node into the context")
    func createInserts() throws {
        let context = try makeContext()
        let node = NodeCommands.createNode(name: "Foo", in: context)
        #expect(node.name == "Foo")
        try context.save()
        let nodes = try context.fetch(FetchDescriptor<Node>())
        #expect(nodes.count == 1)
    }

    @Test("deleteNode removes the node")
    func deleteRemovesNode() throws {
        let context = try makeContext()
        let node = NodeCommands.createNode(name: "Foo", in: context)
        try context.save()

        NodeCommands.deleteNode(node, in: context)
        try context.save()

        let nodes = try context.fetch(FetchDescriptor<Node>())
        #expect(nodes.isEmpty)
    }

    @Test("deleteNode cascades to edges that reference it as source or target")
    func deleteCascadesToEdges() throws {
        let context = try makeContext()
        let a = NodeCommands.createNode(name: "A", in: context)
        let b = NodeCommands.createNode(name: "B", in: context)
        let c = NodeCommands.createNode(name: "C", in: context)
        EdgeCommands.createEdge(from: a.id, to: b.id, in: context)  // touches A
        EdgeCommands.createEdge(from: b.id, to: a.id, in: context)  // touches A
        EdgeCommands.createEdge(from: b.id, to: c.id, in: context)  // does not touch A
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Edge>()).count == 3)

        NodeCommands.deleteNode(a, in: context)
        try context.save()

        let remainingEdges = try context.fetch(FetchDescriptor<Edge>())
        #expect(remainingEdges.count == 1)
        // The surviving edge is B → C — neither endpoint is A.
        #expect(remainingEdges.first?.sourceID == b.id)
        #expect(remainingEdges.first?.targetID == c.id)
    }

    @Test("deleteNode leaves unrelated nodes intact")
    func deleteLeavesUnrelatedNodes() throws {
        let context = try makeContext()
        let a = NodeCommands.createNode(name: "A", in: context)
        _ = NodeCommands.createNode(name: "B", in: context)
        try context.save()

        NodeCommands.deleteNode(a, in: context)
        try context.save()

        let nodes = try context.fetch(FetchDescriptor<Node>())
        #expect(nodes.count == 1)
        #expect(nodes.first?.name == "B")
    }
}
