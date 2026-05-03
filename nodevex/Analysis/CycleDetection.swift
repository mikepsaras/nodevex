import Foundation

enum CycleDetection {
    /// Tarjan's strongly-connected-components algorithm. Returns each SCC as
    /// a list of node IDs. SCCs are returned in reverse topological order.
    static func stronglyConnectedComponents(graph: GraphSnapshot) -> [[UUID]] {
        var outgoing: [UUID: [UUID]] = [:]
        for edge in graph.edges {
            outgoing[edge.sourceID, default: []].append(edge.targetID)
        }

        var state = TarjanState()
        for node in graph.nodes where state.indices[node.id] == nil {
            strongConnect(node.id, outgoing: outgoing, state: &state)
        }
        return state.sccs
    }

    /// Returns SCCs that represent actual cycles — components of size > 1, plus
    /// any single-node SCC that has a self-loop.
    static func cycles(graph: GraphSnapshot) -> [[UUID]] {
        let sccs = stronglyConnectedComponents(graph: graph)
        return sccs.filter { component in
            if component.count > 1 { return true }
            let nodeID = component[0]
            return graph.edges.contains { $0.sourceID == nodeID && $0.targetID == nodeID }
        }
    }

    /// True if the graph contains at least one directed cycle.
    static func hasCycle(graph: GraphSnapshot) -> Bool {
        !cycles(graph: graph).isEmpty
    }

    private struct TarjanState {
        var index = 0
        var stack: [UUID] = []
        var indices: [UUID: Int] = [:]
        var lowLinks: [UUID: Int] = [:]
        var onStack: Set<UUID> = []
        var sccs: [[UUID]] = []
    }

    private static func strongConnect(_ v: UUID, outgoing: [UUID: [UUID]], state: inout TarjanState) {
        state.indices[v] = state.index
        state.lowLinks[v] = state.index
        state.index += 1
        state.stack.append(v)
        state.onStack.insert(v)

        for w in outgoing[v] ?? [] {
            if state.indices[w] == nil {
                strongConnect(w, outgoing: outgoing, state: &state)
                state.lowLinks[v] = min(state.lowLinks[v] ?? 0, state.lowLinks[w] ?? 0)
            } else if state.onStack.contains(w) {
                state.lowLinks[v] = min(state.lowLinks[v] ?? 0, state.indices[w] ?? 0)
            }
        }

        if state.lowLinks[v] == state.indices[v] {
            var component: [UUID] = []
            while true {
                let w = state.stack.removeLast()
                state.onStack.remove(w)
                component.append(w)
                if w == v { break }
            }
            state.sccs.append(component)
        }
    }
}
