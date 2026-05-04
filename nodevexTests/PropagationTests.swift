import Testing
@testable import nodevex

@Suite("Propagation")
struct PropagationTests {
    @Test("pinned root retains its initial value")
    func pinnedRootStays() {
        let a = Node(name: "A")
        let g = GraphSnapshot(nodes: [a], edges: [], categories: [])
        let result = Propagation.propagate(initialValues: [a.id: 1.0], graph: g)
        #expect(result.values[a.id] == 1.0)
    }

    @Test("positive valence carries source value forward")
    func positiveValence() {
        let a = Node(name: "A"), b = Node(name: "B")
        let g = GraphSnapshot(nodes: [a, b], edges: [
            Edge(sourceID: a.id, targetID: b.id, strength: 1.0, valence: .positive)
        ], categories: [])
        let result = Propagation.propagate(initialValues: [a.id: 1.0], graph: g)
        #expect(result.values[b.id] == 1.0)
    }

    @Test("negative valence flips sign downstream")
    func negativeValence() {
        let a = Node(name: "A"), b = Node(name: "B")
        let g = GraphSnapshot(nodes: [a, b], edges: [
            Edge(sourceID: a.id, targetID: b.id, strength: 1.0, valence: .negative)
        ], categories: [])
        let result = Propagation.propagate(initialValues: [a.id: 1.0], graph: g)
        #expect(result.values[b.id] == -1.0)
    }

    @Test("neutral valence contributes zero")
    func neutralValence() {
        let a = Node(name: "A"), b = Node(name: "B")
        let g = GraphSnapshot(nodes: [a, b], edges: [
            Edge(sourceID: a.id, targetID: b.id, strength: 1.0, valence: .neutral)
        ], categories: [])
        let result = Propagation.propagate(initialValues: [a.id: 1.0], graph: g)
        #expect(result.values[b.id] == 0.0)
    }

    @Test("converges before max iterations on a simple positive chain")
    func convergesEarly() {
        let a = Node(name: "A"), b = Node(name: "B")
        let g = GraphSnapshot(nodes: [a, b], edges: [
            Edge(sourceID: a.id, targetID: b.id, strength: 1.0, valence: .positive)
        ], categories: [])
        let result = Propagation.propagate(initialValues: [a.id: 1.0], graph: g, iterations: 100)
        #expect(result.converged)
        #expect(result.iterationsTaken < 100)
    }
}
