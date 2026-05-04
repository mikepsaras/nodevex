import Foundation

enum ShortestPath {
    /// BFS for the shortest path measured in edge count (unweighted). Returns
    /// the sequence of node IDs from source to target inclusive, or nil if no
    /// path exists.
    static func bfs(from source: UUID, to target: UUID, graph: GraphSnapshot) -> [UUID]? {
        if source == target { return [source] }

        var outgoing: [UUID: [UUID]] = [:]
        for edge in graph.edges {
            outgoing[edge.sourceID, default: []].append(edge.targetID)
        }

        var predecessors: [UUID: UUID] = [:]
        var visited: Set<UUID> = [source]
        var queue: [UUID] = [source]
        var head = 0

        while head < queue.count {
            let current = queue[head]
            head += 1
            for next in outgoing[current] ?? [] {
                if visited.contains(next) { continue }
                visited.insert(next)
                predecessors[next] = current
                if next == target {
                    return reconstructPath(to: target, predecessors: predecessors, source: source)
                }
                queue.append(next)
            }
        }
        return nil
    }

    /// Dijkstra's algorithm with edge weight = 1 / strength (so weak edges count
    /// as longer hops). Returns the path or nil if unreachable.
    static func dijkstra(from source: UUID, to target: UUID, graph: GraphSnapshot) -> [UUID]? {
        if source == target { return [source] }

        var outgoing: [UUID: [(UUID, Double)]] = [:]
        for edge in graph.edges {
            let weight = edge.strength > 0 ? 1.0 / edge.strength : .infinity
            outgoing[edge.sourceID, default: []].append((edge.targetID, weight))
        }

        var distances: [UUID: Double] = [:]
        var predecessors: [UUID: UUID] = [:]
        var unvisited: Set<UUID> = []
        for node in graph.nodes {
            distances[node.id] = .infinity
            unvisited.insert(node.id)
        }
        distances[source] = 0

        while !unvisited.isEmpty {
            // Find the unvisited node with minimum distance. Linear scan is fine
            // for the node counts we expect; swap to a heap if it ever isn't.
            var current: UUID?
            var minDist = Double.infinity
            for id in unvisited {
                let d = distances[id] ?? .infinity
                if d < minDist {
                    minDist = d
                    current = id
                }
            }
            guard let u = current, minDist < .infinity else { return nil }
            if u == target {
                return reconstructPath(to: target, predecessors: predecessors, source: source)
            }
            unvisited.remove(u)

            for (v, weight) in outgoing[u] ?? [] where unvisited.contains(v) {
                let alt = (distances[u] ?? .infinity) + weight
                if alt < (distances[v] ?? .infinity) {
                    distances[v] = alt
                    predecessors[v] = u
                }
            }
        }
        return nil
    }

    private static func reconstructPath(to target: UUID, predecessors: [UUID: UUID], source: UUID) -> [UUID] {
        var path: [UUID] = [target]
        var cursor = target
        while let prev = predecessors[cursor] {
            path.append(prev)
            cursor = prev
            if cursor == source { break }
        }
        return path.reversed()
    }
}
