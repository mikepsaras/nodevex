import Testing
@testable import nodevex

@Suite("CycleDetection")
struct CycleDetectionTests {
    @Test("empty graph has no cycles")
    func empty() {
        let g = GraphSnapshot(nodes: [], edges: [], categories: [])
        #expect(CycleDetection.cycles(graph: g).isEmpty)
        #expect(!CycleDetection.hasCycle(graph: g))
    }

    @Test("linear chain is acyclic")
    func linearAcyclic() {
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let g = GraphSnapshot(nodes: [a, b, c], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: c.id)
        ], categories: [])
        #expect(CycleDetection.cycles(graph: g).isEmpty)
        #expect(!CycleDetection.hasCycle(graph: g))
    }

    @Test("self-loop is detected as a cycle")
    func selfLoop() {
        let a = Node(name: "A")
        let g = GraphSnapshot(
            nodes: [a],
            edges: [Edge(sourceID: a.id, targetID: a.id)],
            categories: []
        )
        let cycles = CycleDetection.cycles(graph: g)
        #expect(cycles.count == 1)
        #expect(cycles[0] == [a.id])
    }

    @Test("two-node cycle detected as a single SCC")
    func twoNodeCycle() {
        let a = Node(name: "A"), b = Node(name: "B")
        let g = GraphSnapshot(nodes: [a, b], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: a.id)
        ], categories: [])
        let cycles = CycleDetection.cycles(graph: g)
        #expect(cycles.count == 1)
        #expect(Set(cycles[0]) == Set([a.id, b.id]))
    }

    @Test("DAG component coexisting with a cycle component")
    func mixedGraph() {
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C"), d = Node(name: "D")
        // A → B is a DAG; C ↔ D is a cycle
        let g = GraphSnapshot(nodes: [a, b, c, d], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: c.id, targetID: d.id),
            Edge(sourceID: d.id, targetID: c.id)
        ], categories: [])
        let cycles = CycleDetection.cycles(graph: g)
        #expect(cycles.count == 1)
        #expect(Set(cycles[0]) == Set([c.id, d.id]))
    }
}
