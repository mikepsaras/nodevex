import Testing
@testable import nodevex

@Suite("ShortestPath")
struct ShortestPathTests {
    @Test("BFS source==target returns single-element path")
    func sameSourceTarget() {
        let a = Node(name: "A")
        let g = GraphSnapshot(nodes: [a], edges: [], categories: [])
        #expect(ShortestPath.bfs(from: a.id, to: a.id, graph: g) == [a.id])
    }

    @Test("BFS prefers fewer hops over more hops")
    func bfsShortestHops() {
        // A → B → C, plus a direct A → C shortcut.
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let g = GraphSnapshot(nodes: [a, b, c], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: c.id),
            Edge(sourceID: a.id, targetID: c.id)
        ], categories: [])
        #expect(ShortestPath.bfs(from: a.id, to: c.id, graph: g) == [a.id, c.id])
    }

    @Test("BFS returns nil when target unreachable")
    func bfsUnreachable() {
        let a = Node(name: "A"), b = Node(name: "B")
        let g = GraphSnapshot(nodes: [a, b], edges: [], categories: [])
        #expect(ShortestPath.bfs(from: a.id, to: b.id, graph: g) == nil)
    }

    @Test("Dijkstra prefers strong-edge multi-hop over weak-edge direct")
    func dijkstraPrefersStrength() {
        // A → C: strength 0.1 (weight = 1/0.1 = 10) — direct
        // A → B → C: each strength 1.0 (weight 1+1 = 2) — two hops
        // Dijkstra should pick the cheaper two-hop path.
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let g = GraphSnapshot(nodes: [a, b, c], edges: [
            Edge(sourceID: a.id, targetID: c.id, strength: 0.1),
            Edge(sourceID: a.id, targetID: b.id, strength: 1.0),
            Edge(sourceID: b.id, targetID: c.id, strength: 1.0)
        ], categories: [])
        #expect(ShortestPath.dijkstra(from: a.id, to: c.id, graph: g) == [a.id, b.id, c.id])
    }

    @Test("Dijkstra returns nil when target unreachable")
    func dijkstraUnreachable() {
        let a = Node(name: "A"), b = Node(name: "B")
        let g = GraphSnapshot(nodes: [a, b], edges: [], categories: [])
        #expect(ShortestPath.dijkstra(from: a.id, to: b.id, graph: g) == nil)
    }
}
