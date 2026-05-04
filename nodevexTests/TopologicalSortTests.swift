import Testing
@testable import nodevex

@Suite("TopologicalSort")
struct TopologicalSortTests {
    @Test("empty graph returns empty order")
    func empty() throws {
        let result = try TopologicalSort.sort(graph: GraphSnapshot(nodes: [], edges: [], categories: []))
        #expect(result.isEmpty)
    }

    @Test("single isolated node")
    func single() throws {
        let n = Node(name: "A")
        let result = try TopologicalSort.sort(graph: GraphSnapshot(nodes: [n], edges: [], categories: []))
        #expect(result == [n.id])
    }

    @Test("linear chain orders source-to-sink")
    func linearChain() throws {
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C")
        let edges = [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: c.id)
        ]
        let result = try TopologicalSort.sort(
            graph: GraphSnapshot(nodes: [a, b, c], edges: edges, categories: [])
        )
        #expect(result == [a.id, b.id, c.id])
    }

    @Test("diamond has source first and sink last")
    func diamond() throws {
        let a = Node(name: "A"), b = Node(name: "B"), c = Node(name: "C"), d = Node(name: "D")
        let edges = [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: a.id, targetID: c.id),
            Edge(sourceID: b.id, targetID: d.id),
            Edge(sourceID: c.id, targetID: d.id)
        ]
        let result = try TopologicalSort.sort(
            graph: GraphSnapshot(nodes: [a, b, c, d], edges: edges, categories: [])
        )
        #expect(result.first == a.id)
        #expect(result.last == d.id)
    }

    @Test("cycle throws containsCycle")
    func cycleThrows() {
        let a = Node(name: "A"), b = Node(name: "B")
        let edges = [
            Edge(sourceID: a.id, targetID: b.id),
            Edge(sourceID: b.id, targetID: a.id)
        ]
        #expect(throws: TopologicalSort.SortError.containsCycle) {
            try TopologicalSort.sort(
                graph: GraphSnapshot(nodes: [a, b], edges: edges, categories: [])
            )
        }
    }
}
