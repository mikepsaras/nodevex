import Testing
import CoreGraphics
@testable import arachnode

@Suite("LayoutEngine")
struct LayoutEngineTests {
    @Test("isDragging tracks the drag lifecycle")
    func isDraggingLifecycle() {
        let engine = LayoutEngine()
        let a = Node(name: "A")
        engine.applyGraphChange(GraphSnapshot(nodes: [a], edges: [], categories: []))

        #expect(!engine.isDragging)
        engine.startDrag(nodeID: a.id, position: CGPoint(x: 50, y: 50))
        #expect(engine.isDragging)
        engine.endDrag()
        #expect(!engine.isDragging)
    }

    @Test("drag override pins the dragged node to the target position")
    func dragOverridePinsNode() {
        let engine = LayoutEngine()
        let a = Node(name: "A")
        engine.applyGraphChange(GraphSnapshot(nodes: [a], edges: [], categories: []))

        let target = CGPoint(x: 123, y: -45)
        engine.startDrag(nodeID: a.id, position: target)
        engine.tick()
        #expect(engine.positions[a.id] == target)
    }

    @Test("updateDrag moves the dragged node to the new position")
    func updateDragRetargets() {
        let engine = LayoutEngine()
        let a = Node(name: "A")
        engine.applyGraphChange(GraphSnapshot(nodes: [a], edges: [], categories: []))

        engine.startDrag(nodeID: a.id, position: CGPoint(x: 10, y: 10))
        engine.tick()
        engine.updateDrag(position: CGPoint(x: 99, y: -7))
        engine.tick()
        #expect(engine.positions[a.id] == CGPoint(x: 99, y: -7))
    }

    @Test("seed origin offsets new node positions")
    func seedOriginOffsetsNewNodes() {
        // New nodes seed within ~80pt of seedOrigin, never at the canvas
        // origin. This is what makes new nodes spawn near the viewport
        // center rather than always at (0, 0).
        let engine = LayoutEngine()
        let a = Node(name: "A")
        let snapshot = GraphSnapshot(nodes: [a], edges: [], categories: [])
        engine.applyGraphChange(snapshot, seedOrigin: CGPoint(x: 500, y: 300))

        guard let pos = engine.positions[a.id] else {
            Issue.record("expected position for seeded node")
            return
        }
        #expect(abs(pos.x - 500) < 100)
        #expect(abs(pos.y - 300) < 100)
    }
}
