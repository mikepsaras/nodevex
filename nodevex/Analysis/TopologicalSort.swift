import Foundation

enum TopologicalSort {
    enum SortError: Error {
        case containsCycle
    }

    /// Kahn's algorithm. Returns a linear ordering of nodes such that for every
    /// edge u → v, u comes before v in the result. Throws if the graph has a
    /// cycle (no valid topological order).
    static func sort(graph: GraphSnapshot) throws -> [UUID] {
        var inDegree: [UUID: Int] = [:]
        var outgoing: [UUID: [UUID]] = [:]
        for node in graph.nodes {
            inDegree[node.id] = 0
            outgoing[node.id] = []
        }
        for edge in graph.edges {
            inDegree[edge.targetID, default: 0] += 1
            outgoing[edge.sourceID, default: []].append(edge.targetID)
        }

        // Stable order: process roots in the order they appear in graph.nodes.
        var queue: [UUID] = graph.nodes.compactMap { (inDegree[$0.id] ?? 0) == 0 ? $0.id : nil }
        var head = 0
        var result: [UUID] = []
        result.reserveCapacity(graph.nodes.count)

        while head < queue.count {
            let node = queue[head]
            head += 1
            result.append(node)
            for next in outgoing[node] ?? [] {
                inDegree[next, default: 0] -= 1
                if inDegree[next] == 0 {
                    queue.append(next)
                }
            }
        }

        if result.count != graph.nodes.count {
            throw SortError.containsCycle
        }
        return result
    }
}
