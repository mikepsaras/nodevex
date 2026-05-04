import Testing
@testable import nodevex

@Suite("Centrality")
struct CentralityTests {
    @Test("PageRank values sum to ~1 on a 3-cycle")
    func pageRankNormalization() {
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let g = GraphSnapshot(nodes: [a, b, c], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: c.id),
            Edge(sourceID: c.id, targetID: a.id)
        ], categories: [])
        let total = Centrality.pageRank(graph: g).values.reduce(0, +)
        #expect(abs(total - 1.0) < 0.01)
    }

    @Test("PageRank hub outranks every spoke pointing into it")
    func pageRankHubOutranksSpokes() {
        let hub = Node(name: "hub")
        let s1 = Node(name: "s1"), s2 = Node(name: "s2"), s3 = Node(name: "s3")
        let g = GraphSnapshot(nodes: [hub, s1, s2, s3], edges: [
            Edge(sourceID: s1.id, targetID: hub.id),
            Edge(sourceID: s2.id, targetID: hub.id),
            Edge(sourceID: s3.id, targetID: hub.id)
        ], categories: [])
        let ranks = Centrality.pageRank(graph: g)
        let hubRank = ranks[hub.id] ?? 0
        for spoke in [s1, s2, s3] {
            #expect(hubRank > (ranks[spoke.id] ?? 0))
        }
    }

    @Test("Betweenness is highest for the middle node of a chain")
    func betweennessChainMiddle() {
        // A → B → C — B is on the only path from A to C.
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let g = GraphSnapshot(nodes: [a, b, c], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: c.id)
        ], categories: [])
        let scores = Centrality.betweenness(graph: g)
        #expect((scores[b.id] ?? 0) > (scores[a.id] ?? 0))
        #expect((scores[b.id] ?? 0) > (scores[c.id] ?? 0))
    }

    @Test("Eigenvector returns a value for every node")
    func eigenvectorCoversAllNodes() {
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let g = GraphSnapshot(nodes: [a, b, c], edges: [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: c.id),
            Edge(sourceID: c.id, targetID: a.id)
        ], categories: [])
        let values = Centrality.eigenvector(graph: g)
        #expect(values.count == 3)
        #expect(values[a.id] != nil)
        #expect(values[b.id] != nil)
        #expect(values[c.id] != nil)
    }
}
