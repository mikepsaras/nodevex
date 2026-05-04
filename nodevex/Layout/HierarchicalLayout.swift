import Foundation
import CoreGraphics

/// Sugiyama-style layered layout. Top-to-bottom by causal depth — sources at
/// the top, sinks at the bottom, edges drawn primarily downward. Cycles are
/// handled by removing DFS-discovered back edges from the layering graph (the
/// edges still render, they just don't constrain depth).
///
/// Pipeline:
/// 1. DFS over the directed graph to identify back edges. Removing them yields
///    a DAG suitable for layering.
/// 2. Longest-path layer assignment: each node's layer is `1 + max(predecessor
///    layers)`. Source nodes (no incoming non-back edges) sit at layer 0.
/// 3. Barycenter crossing-reduction sweeps — alternate top-down and bottom-up
///    passes ordering each layer by the average position of its neighbors in
///    the adjacent layer. Four passes is enough to converge in practice.
/// 4. Coordinate assignment: y by layer, x by within-layer index. The whole
///    block is centered on the origin to match the existing
///    canvas-center-relative coordinate convention used by ForceDirectedLayout
///    and the renderer.
struct HierarchicalLayout: LayoutStrategy {
    let name = "Hierarchical"

    private let layerSpacing: CGFloat = 110
    private let nodeSpacing: CGFloat = 90
    private let crossingReductionPasses = 4

    func compute(graph: GraphSnapshot, previousPositions: [UUID: CGPoint]) -> [UUID: CGPoint] {
        guard !graph.nodes.isEmpty else { return [:] }
        let nodeIDs = graph.nodes.map { $0.id }

        var allOutgoing: [UUID: [UUID]] = [:]
        for edge in graph.edges {
            allOutgoing[edge.sourceID, default: []].append(edge.targetID)
        }
        let backEdges = findBackEdges(nodes: nodeIDs, outgoing: allOutgoing)

        // Build the layering graph (excludes back edges).
        var outgoing: [UUID: [UUID]] = [:]
        var incoming: [UUID: [UUID]] = [:]
        for edge in graph.edges {
            if backEdges.contains(EdgeKey(source: edge.sourceID, target: edge.targetID)) {
                continue
            }
            outgoing[edge.sourceID, default: []].append(edge.targetID)
            incoming[edge.targetID, default: []].append(edge.sourceID)
        }

        let layerOf = assignLayers(nodes: nodeIDs, incoming: incoming)
        let maxLayer = layerOf.values.max() ?? 0
        var layers: [[UUID]] = Array(repeating: [], count: maxLayer + 1)
        // Stable initial order: graph.nodes iteration order, so pre-existing
        // positions don't get scrambled before crossing reduction.
        for nodeID in nodeIDs {
            let l = layerOf[nodeID] ?? 0
            layers[l].append(nodeID)
        }

        for _ in 0..<crossingReductionPasses {
            for i in 1..<layers.count {
                layers[i] = orderByBarycenter(
                    nodes: layers[i],
                    neighborLayer: layers[i - 1],
                    edges: incoming
                )
            }
            if layers.count >= 2 {
                for i in stride(from: layers.count - 2, through: 0, by: -1) {
                    layers[i] = orderByBarycenter(
                        nodes: layers[i],
                        neighborLayer: layers[i + 1],
                        edges: outgoing
                    )
                }
            }
        }

        return assignCoordinates(layers: layers)
    }

    private struct EdgeKey: Hashable {
        let source: UUID
        let target: UUID
    }

    private enum DFSColor { case white, gray, black }

    /// DFS-based back-edge detection. An edge `u → v` is a back edge iff `v`
    /// is on the current recursion stack (gray) when we traverse it. Removing
    /// the back edges from the graph yields a DAG.
    private func findBackEdges(nodes: [UUID], outgoing: [UUID: [UUID]]) -> Set<EdgeKey> {
        var color: [UUID: DFSColor] = [:]
        var backEdges: Set<EdgeKey> = []

        func dfs(_ node: UUID) {
            color[node] = .gray
            for next in outgoing[node] ?? [] {
                switch color[next] ?? .white {
                case .white:
                    dfs(next)
                case .gray:
                    backEdges.insert(EdgeKey(source: node, target: next))
                case .black:
                    break
                }
            }
            color[node] = .black
        }

        for node in nodes where (color[node] ?? .white) == .white {
            dfs(node)
        }
        return backEdges
    }

    /// Longest-path layering on the DAG. Each node's layer is one greater than
    /// the deepest predecessor; sources (no incoming) settle at layer 0. The
    /// fixed-point iteration converges in at most `n` passes.
    private func assignLayers(nodes: [UUID], incoming: [UUID: [UUID]]) -> [UUID: Int] {
        var layer: [UUID: Int] = Dictionary(uniqueKeysWithValues: nodes.map { ($0, 0) })
        var changed = true
        var iterations = 0
        let maxIterations = nodes.count + 1

        while changed && iterations < maxIterations {
            changed = false
            iterations += 1
            for node in nodes {
                let preds = incoming[node] ?? []
                if preds.isEmpty { continue }
                guard let predMaxLayer = preds.compactMap({ layer[$0] }).max() else { continue }
                let newLayer = predMaxLayer + 1
                if newLayer > (layer[node] ?? 0) {
                    layer[node] = newLayer
                    changed = true
                }
            }
        }
        return layer
    }

    /// Sort `nodes` by barycenter — the average index in `neighborLayer` of
    /// each node's neighbors via `edges`. Nodes with no neighbors keep their
    /// existing relative order (stable tiebreak by original index).
    private func orderByBarycenter(
        nodes: [UUID],
        neighborLayer: [UUID],
        edges: [UUID: [UUID]]
    ) -> [UUID] {
        let neighborIndex: [UUID: Int] = Dictionary(
            uniqueKeysWithValues: neighborLayer.enumerated().map { ($0.element, $0.offset) }
        )
        let withScore: [(node: UUID, score: Double, originalIndex: Int)] = nodes.enumerated().map { offset, node in
            let neighbors = edges[node] ?? []
            let positions = neighbors.compactMap { neighborIndex[$0] }
            let score: Double
            if positions.isEmpty {
                score = Double(offset)
            } else {
                score = Double(positions.reduce(0, +)) / Double(positions.count)
            }
            return (node, score, offset)
        }
        return withScore
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.originalIndex < rhs.originalIndex : lhs.score < rhs.score
            }
            .map { $0.node }
    }

    private func assignCoordinates(layers: [[UUID]]) -> [UUID: CGPoint] {
        let layerCount = layers.count
        let totalHeight = CGFloat(max(layerCount - 1, 0)) * layerSpacing
        let topY = -totalHeight / 2

        var positions: [UUID: CGPoint] = [:]
        for (layerIndex, layerNodes) in layers.enumerated() {
            let y = topY + CGFloat(layerIndex) * layerSpacing
            let layerWidth = CGFloat(max(layerNodes.count - 1, 0)) * nodeSpacing
            let startX = -layerWidth / 2
            for (i, nodeID) in layerNodes.enumerated() {
                let x = startX + CGFloat(i) * nodeSpacing
                positions[nodeID] = CGPoint(x: x, y: y)
            }
        }
        return positions
    }
}
