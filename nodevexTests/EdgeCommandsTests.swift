import Testing
import SwiftData
@testable import nodevex

@Suite("EdgeCommands")
@MainActor
struct EdgeCommandsTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Node.self, Edge.self, Category.self,
            configurations: config
        )
        return ModelContext(container)
    }

    @Test("creates a normal edge")
    func createsEdge() throws {
        let context = try makeContext()
        let a = Node(name: "A"), b = Node(name: "B")
        context.insert(a)
        context.insert(b)
        let edge = EdgeCommands.createEdge(from: a.id, to: b.id, in: context)
        #expect(edge != nil)
    }

    @Test("rejects a self-edge")
    func rejectsSelfEdge() throws {
        let context = try makeContext()
        let a = Node(name: "A")
        context.insert(a)
        let result = EdgeCommands.createEdge(from: a.id, to: a.id, in: context)
        #expect(result == nil)
    }

    @Test("rejects a duplicate (source, target) pair")
    func rejectsDuplicate() throws {
        let context = try makeContext()
        let a = Node(name: "A"), b = Node(name: "B")
        context.insert(a)
        context.insert(b)
        _ = EdgeCommands.createEdge(from: a.id, to: b.id, in: context)
        let dup = EdgeCommands.createEdge(from: a.id, to: b.id, in: context)
        #expect(dup == nil)
    }

    @Test("allows the reverse direction even when the forward edge exists")
    func allowsReverseDirection() throws {
        let context = try makeContext()
        let a = Node(name: "A"), b = Node(name: "B")
        context.insert(a)
        context.insert(b)
        _ = EdgeCommands.createEdge(from: a.id, to: b.id, in: context)
        let reverse = EdgeCommands.createEdge(from: b.id, to: a.id, in: context)
        #expect(reverse != nil)
    }
}
