import Testing
import CoreGraphics
@testable import nodevex

@Suite("HierarchicalLayout")
struct HierarchicalLayoutTests {
    private let layout = HierarchicalLayout()

    @Test("empty graph produces empty result")
    func empty() {
        let result = layout.compute(
            graph: GraphSnapshot(nodes: [], edges: [], categories: []),
            previousPositions: [:]
        )
        #expect(result.isEmpty)
    }

    @Test("single node lands at the origin")
    func single() {
        let a = Node(name: "A")
        let result = layout.compute(
            graph: GraphSnapshot(nodes: [a], edges: [], categories: []),
            previousPositions: [:]
        )
        #expect(result[a.id] == .zero)
    }

    @Test("linear chain stacks one node per layer in source-to-sink order")
    func linearChain() {
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let g = GraphSnapshot(nodes: [a, b, c], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: c.id)
        ], categories: [])
        let result = layout.compute(graph: g, previousPositions: [:])
        guard let posA = result[a.id],
              let posB = result[b.id],
              let posC = result[c.id] else {
            Issue.record("missing positions for chain")
            return
        }
        // Smaller y = earlier layer (source side); single-node-wide layers
        // sit on the centerline.
        #expect(posA.y < posB.y)
        #expect(posB.y < posC.y)
        #expect(posA.x == 0)
        #expect(posB.x == 0)
        #expect(posC.x == 0)
    }

    @Test("diamond puts the source up top, the sink at bottom, middle row shared")
    func diamond() {
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C"), d = Node(name: "D")
        let g = GraphSnapshot(nodes: [a, b, c, d], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: a.id, targetID: c.id),
            Edge(sourceID: b.id, targetID: d.id),
            Edge(sourceID: c.id, targetID: d.id)
        ], categories: [])
        let result = layout.compute(graph: g, previousPositions: [:])
        guard let posA = result[a.id],
              let posB = result[b.id],
              let posC = result[c.id],
              let posD = result[d.id] else {
            Issue.record("missing positions for diamond")
            return
        }
        // A is the only source, D the only sink; B and C share the middle layer.
        #expect(posA.y < posB.y)
        #expect(posA.y < posC.y)
        #expect(posD.y > posB.y)
        #expect(posD.y > posC.y)
        #expect(posB.y == posC.y)
    }

    @Test("cycle still produces a layout — back edges ignored for layering")
    func cycleStillLayouts() {
        // Three-node cycle: A → B → C → A. Without back-edge handling, every
        // node would be in conflict. The algorithm strips one back edge for
        // layering and produces a stable layout for all three nodes.
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let g = GraphSnapshot(nodes: [a, b, c], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: c.id),
            Edge(sourceID: c.id, targetID: a.id)
        ], categories: [])
        let result = layout.compute(graph: g, previousPositions: [:])
        #expect(result.count == 3)
        #expect(result[a.id] != nil)
        #expect(result[b.id] != nil)
        #expect(result[c.id] != nil)
    }

    @Test("self-loop doesn't break layering")
    func selfLoop() {
        let a = Node(name: "A")
        let g = GraphSnapshot(nodes: [a], edges: [
            Edge(sourceID: a.id, targetID: a.id)
        ], categories: [])
        let result = layout.compute(graph: g, previousPositions: [:])
        #expect(result.count == 1)
        #expect(result[a.id] != nil)
    }

    @Test("disconnected components both get positions")
    func disconnectedComponents() {
        let a = Node(name: "A"), b = Node(name: "B")
        let c = Node(name: "C"), d = Node(name: "D")
        let g = GraphSnapshot(nodes: [a, b, c, d], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: c.id, targetID: d.id)
        ], categories: [])
        let result = layout.compute(graph: g, previousPositions: [:])
        #expect(result.count == 4)
        for node in [a, b, c, d] {
            #expect(result[node.id] != nil)
        }
    }
}
