import Foundation

enum Centrality {
    /// PageRank via power iteration. Returns rank ∈ (0, 1] per node, sums to ~1.
    /// Iterates up to `iterations` times or stops early when the largest
    /// single-step change drops below `convergenceThreshold`.
    static func pageRank(
        graph: GraphSnapshot,
        dampingFactor: Double = 0.85,
        iterations: Int = 50,
        convergenceThreshold: Double = 0.0001
    ) -> [UUID: Double] {
        guard !graph.nodes.isEmpty else { return [:] }
        let n = Double(graph.nodes.count)

        var ranks: [UUID: Double] = [:]
        for node in graph.nodes { ranks[node.id] = 1.0 / n }

        var outDegree: [UUID: Int] = [:]
        var incoming: [UUID: [UUID]] = [:]
        for edge in graph.edges {
            outDegree[edge.sourceID, default: 0] += 1
            incoming[edge.targetID, default: []].append(edge.sourceID)
        }

        let teleport = (1.0 - dampingFactor) / n

        for _ in 0..<iterations {
            var newRanks: [UUID: Double] = [:]
            // Dangling-node mass redistributes uniformly so totals stay normalized.
            var danglingMass = 0.0
            for node in graph.nodes where (outDegree[node.id] ?? 0) == 0 {
                danglingMass += ranks[node.id] ?? 0
            }
            let danglingShare = dampingFactor * danglingMass / n

            var maxDelta = 0.0
            for node in graph.nodes {
                var sum = 0.0
                for source in incoming[node.id] ?? [] {
                    let outDeg = max(outDegree[source] ?? 1, 1)
                    sum += (ranks[source] ?? 0) / Double(outDeg)
                }
                let newValue = teleport + danglingShare + dampingFactor * sum
                newRanks[node.id] = newValue
                let delta = abs(newValue - (ranks[node.id] ?? 0))
                if delta > maxDelta { maxDelta = delta }
            }
            ranks = newRanks
            if maxDelta < convergenceThreshold { break }
        }
        return ranks
    }

    /// Brandes' algorithm for betweenness centrality. Returns the unnormalized
    /// number of shortest paths through each node, summed over all source-target
    /// pairs.
    static func betweenness(graph: GraphSnapshot) -> [UUID: Double] {
        guard !graph.nodes.isEmpty else { return [:] }

        var outgoing: [UUID: [UUID]] = [:]
        for edge in graph.edges {
            outgoing[edge.sourceID, default: []].append(edge.targetID)
        }

        var centrality: [UUID: Double] = [:]
        for node in graph.nodes { centrality[node.id] = 0 }

        for sNode in graph.nodes {
            let s = sNode.id
            var stack: [UUID] = []
            var predecessors: [UUID: [UUID]] = [:]
            var sigma: [UUID: Double] = [:]
            var distance: [UUID: Int] = [:]
            for node in graph.nodes {
                predecessors[node.id] = []
                sigma[node.id] = 0
                distance[node.id] = -1
            }
            sigma[s] = 1
            distance[s] = 0

            var queue: [UUID] = [s]
            var head = 0
            while head < queue.count {
                let v = queue[head]
                head += 1
                stack.append(v)
                for w in outgoing[v] ?? [] {
                    if (distance[w] ?? -1) < 0 {
                        queue.append(w)
                        distance[w] = (distance[v] ?? 0) + 1
                    }
                    if distance[w] == (distance[v] ?? 0) + 1 {
                        sigma[w, default: 0] += sigma[v] ?? 0
                        predecessors[w, default: []].append(v)
                    }
                }
            }

            var delta: [UUID: Double] = [:]
            for node in graph.nodes { delta[node.id] = 0 }
            while let w = stack.popLast() {
                for v in predecessors[w] ?? [] {
                    let sw = sigma[w] ?? 0
                    guard sw > 0 else { continue }
                    let contribution = ((sigma[v] ?? 0) / sw) * (1 + (delta[w] ?? 0))
                    delta[v, default: 0] += contribution
                }
                if w != s {
                    centrality[w, default: 0] += delta[w] ?? 0
                }
            }
        }

        return centrality
    }

    /// Eigenvector centrality via power iteration. Result is L2-normalized so
    /// values across nodes are directly comparable. Iterates up to `iterations`
    /// times or stops early when the largest single-step change drops below
    /// `convergenceThreshold`.
    static func eigenvector(
        graph: GraphSnapshot,
        iterations: Int = 50,
        convergenceThreshold: Double = 0.0001
    ) -> [UUID: Double] {
        guard !graph.nodes.isEmpty else { return [:] }

        var values: [UUID: Double] = [:]
        for node in graph.nodes { values[node.id] = 1.0 }

        var incoming: [UUID: [UUID]] = [:]
        for edge in graph.edges {
            incoming[edge.targetID, default: []].append(edge.sourceID)
        }

        for _ in 0..<iterations {
            var newValues: [UUID: Double] = [:]
            for node in graph.nodes {
                var sum = 0.0
                for source in incoming[node.id] ?? [] {
                    sum += values[source] ?? 0
                }
                newValues[node.id] = sum
            }
            // L2 normalize so iteration doesn't blow up or collapse to zero.
            let norm = sqrt(newValues.values.reduce(0) { $0 + $1 * $1 })
            if norm > 0 {
                for (id, v) in newValues {
                    newValues[id] = v / norm
                }
            }
            var maxDelta = 0.0
            for node in graph.nodes {
                let delta = abs((newValues[node.id] ?? 0) - (values[node.id] ?? 0))
                if delta > maxDelta { maxDelta = delta }
            }
            values = newValues
            if maxDelta < convergenceThreshold { break }
        }
        return values
    }
}
