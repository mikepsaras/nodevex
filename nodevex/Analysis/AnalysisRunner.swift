import Foundation

/// Throwaway debug surface for exercising every Tier-1 algorithm against the
/// current graph and printing the results to stdout. Triggered from
/// DocumentView via ⌘⇧A. Replace with proper UI surfaces once visualization
/// decisions land.
enum AnalysisRunner {
    static func runAll(graph: GraphSnapshot) {
        let nameByID: [UUID: String] = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0.name) })
        func name(_ id: UUID) -> String { nameByID[id] ?? id.uuidString.prefix(8).description }

        print("\n========== Graph Analysis ==========")
        print("Nodes: \(graph.nodes.count)   Edges: \(graph.edges.count)   Categories: \(graph.categories.count)")
        guard !graph.nodes.isEmpty else {
            print("(empty graph — nothing to analyze)")
            print("====================================\n")
            return
        }

        print("\n— Edges (raw) —")
        for edge in graph.edges {
            print(String(format: "  %@ → %@   valence=%@   strength=%.2f",
                         name(edge.sourceID), name(edge.targetID),
                         edge.valence.rawValue, edge.strength))
        }

        // --- Cycles ---
        print("\n— Cycles —")
        let cycles = CycleDetection.cycles(graph: graph)
        if cycles.isEmpty {
            print("none (graph is acyclic)")
        } else {
            for (i, c) in cycles.enumerated() {
                print("  cycle \(i + 1): \(c.map(name).joined(separator: " → "))")
            }
        }

        // --- Topological sort ---
        print("\n— Topological Sort —")
        do {
            let order = try TopologicalSort.sort(graph: graph)
            print("  " + order.map(name).joined(separator: " → "))
        } catch {
            print("  contains cycle — no valid order")
        }

        // --- Shortest paths ---
        print("\n— Shortest Path (first node → last node) —")
        if graph.nodes.count >= 2 {
            let src = graph.nodes.first!.id
            let dst = graph.nodes.last!.id
            print("  from: \(name(src))    to: \(name(dst))")
            if let bfs = ShortestPath.bfs(from: src, to: dst, graph: graph) {
                print("  BFS (\(bfs.count - 1) hops): " + bfs.map(name).joined(separator: " → "))
            } else {
                print("  BFS: no path")
            }
            if let dij = ShortestPath.dijkstra(from: src, to: dst, graph: graph) {
                print("  Dijkstra (\(dij.count - 1) hops, weighted): " + dij.map(name).joined(separator: " → "))
            } else {
                print("  Dijkstra: no path")
            }
        } else {
            print("  (need at least 2 nodes)")
        }

        // --- Centrality ---
        print("\n— PageRank (top 5) —")
        for (id, score) in topN(Centrality.pageRank(graph: graph), n: 5) {
            print(String(format: "  %@  %.4f", name(id), score))
        }

        print("\n— Betweenness (top 5) —")
        for (id, score) in topN(Centrality.betweenness(graph: graph), n: 5) {
            print(String(format: "  %@  %.4f", name(id), score))
        }

        print("\n— Eigenvector (top 5) —")
        for (id, score) in topN(Centrality.eigenvector(graph: graph), n: 5) {
            print(String(format: "  %@  %.4f", name(id), score))
        }

        // --- Propagation ---
        print("\n— Propagation (pin first node = 1.0) —")
        let pinned: [UUID: Double] = [graph.nodes.first!.id: 1.0]
        let result = Propagation.propagate(initialValues: pinned, graph: graph)
        let suffix = result.converged ? "converged" : "did not converge"
        print("  iterations: \(result.iterationsTaken)  (\(suffix))")
        for (id, value) in topN(result.values, n: 5) {
            print(String(format: "  %@  %.4f", name(id), value))
        }

        print("====================================\n")
    }

    private static func topN(_ values: [UUID: Double], n: Int) -> [(UUID, Double)] {
        values.sorted { $0.value > $1.value }.prefix(n).map { ($0.key, $0.value) }
    }
}
