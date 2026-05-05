import Testing
import SwiftData
import Foundation
@testable import arachnode

/// Verifies that SwiftData's automatic undo/redo machinery rolls back
/// model mutations when an UndoManager is attached to the context. This is
/// the data-layer half of the ⌘Z story; UI keystroke wiring is exercised
/// at runtime via `.modelContainer(isUndoEnabled: true)`.
@Suite("Undo")
@MainActor
struct UndoTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Node.self, Edge.self, Category.self,
            configurations: config
        )
        let context = ModelContext(container)
        context.undoManager = UndoManager()
        return context
    }

    @Test("undo removes a node that was just created")
    func undoCreateNode() throws {
        let context = try makeContext()
        NodeCommands.createNode(name: "Foo", in: context)
        try context.save()

        var nodes = try context.fetch(FetchDescriptor<Node>())
        #expect(nodes.count == 1)

        context.undoManager?.undo()
        nodes = try context.fetch(FetchDescriptor<Node>())
        #expect(nodes.isEmpty)
    }

    @Test("redo restores a node that was just undone")
    func redoCreateNode() throws {
        let context = try makeContext()
        NodeCommands.createNode(name: "Foo", in: context)
        try context.save()

        context.undoManager?.undo()
        #expect(try context.fetch(FetchDescriptor<Node>()).isEmpty)

        context.undoManager?.redo()
        #expect(try context.fetch(FetchDescriptor<Node>()).count == 1)
    }
}
