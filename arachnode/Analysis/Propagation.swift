import Foundation

enum Propagation {
    struct Result {
        let values: [UUID: Double]
        let iterationsTaken: Int
        let converged: Bool
    }

    /// Iteratively propagates `initialValues` through the graph's edges. On each
    /// iteration, every non-pinned node's new value is the sum of contributions
    /// from incoming edges, where each contribution is
    /// `sourceValue × edgeStrength × signedValence`:
    ///
    /// - positive valence → +1 sign
    /// - negative valence → −1 sign
    /// - neutral valence  →  0 sign (passes through unchanged structure but
    ///   contributes no signed influence)
    ///
    /// Nodes present in `initialValues` are treated as **pinned roots** — their
    /// values stay fixed across iterations. All other nodes start at 0.
    ///
    /// Iterates up to `iterations` times or until the largest single-step value
    /// change drops below `convergenceThreshold`.
    /// Convenience: pins every node whose intrinsic `value` is non-zero as a
    /// propagation root, then runs the same iterative propagation. Lets
    /// callers drive propagation directly from the model without building
    /// the `[UUID: Double]` map themselves.
    static func propagate(
        graph: GraphSnapshot,
        iterations: Int = 100,
        convergenceThreshold: Double = 0.001
    ) -> Result {
        var initialValues: [UUID: Double] = [:]
        for node in graph.nodes where node.value != 0 {
            initialValues[node.id] = node.value
        }
        return propagate(
            initialValues: initialValues,
            graph: graph,
            iterations: iterations,
            convergenceThreshold: convergenceThreshold
        )
    }

    static func propagate(
        initialValues: [UUID: Double],
        graph: GraphSnapshot,
        iterations: Int = 100,
        convergenceThreshold: Double = 0.001
    ) -> Result {
        var values: [UUID: Double] = [:]
        for node in graph.nodes {
            values[node.id] = initialValues[node.id] ?? 0
        }

        // Precompute incoming edges (source, signed contribution coefficient).
        var incoming: [UUID: [(source: UUID, coefficient: Double)]] = [:]
        for edge in graph.edges {
            let sign: Double
            switch edge.valence {
            case .positive: sign = 1
            case .negative: sign = -1
            case .neutral: sign = 0
            }
            let coefficient = edge.strength * sign
            incoming[edge.targetID, default: []].append((edge.sourceID, coefficient))
        }

        for iter in 0..<iterations {
            var newValues = values
            var maxDelta = 0.0
            for node in graph.nodes {
                if initialValues[node.id] != nil {
                    continue  // pinned root — value stays fixed
                }
                var sum = 0.0
                for (source, coefficient) in incoming[node.id] ?? [] {
                    sum += (values[source] ?? 0) * coefficient
                }
                newValues[node.id] = sum
                let delta = abs(sum - (values[node.id] ?? 0))
                if delta > maxDelta { maxDelta = delta }
            }
            values = newValues
            if maxDelta < convergenceThreshold {
                return Result(values: values, iterationsTaken: iter + 1, converged: true)
            }
        }
        return Result(values: values, iterationsTaken: iterations, converged: false)
    }
}
