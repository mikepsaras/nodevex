import Foundation
import CoreGraphics

/// Tick-based force simulation. `LayoutEngine` calls `advance(...)` every
/// frame while alpha > threshold, and `seedPositions(...)` when the graph
/// changes. This is the perturb-and-restore model: continuous physics, alpha
/// decays each tick toward 0, drag perturbs alpha back to 1.0.
///
/// Forces (Fruchterman-Reingold variant):
/// - Inverse-square repulsion between all node pairs
/// - Edge springs (attraction proportional to distance²)
/// - Category clustering (Hooke-style attraction between same-category nodes)
/// - Gentle gravity toward the world origin (the only recentering force —
///   the canvas is effectively infinite, so the graph self-centers via gravity
///   rather than any hard clamp)
struct ForceDirectedLayout {
    private let repulsionConstant: CGFloat = 1_800_000
    private let minRepulsionDistance: CGFloat = 25
    private let idealEdgeLength: CGFloat = 100
    private let gravityStrength: CGFloat = 0.15
    /// Linear pull between same-category nodes. Old batch used 0.08, which
    /// was effectively much stronger in 60-iteration batch mode under cooling
    /// temperature. In continuous mode, it has to compete with the
    /// inverse-square repulsion of every other node *between* a categorized
    /// pair — the clustering equilibrium distance is ~`(repulsion / strength)
    /// ^ (1/3)`, so 0.5 puts it around 150pt vs 0.08's ~280pt.
    private let categoryClusterStrength: CGFloat = 0.5
    private let velocityDecay: CGFloat = 0.4
    private let maxForcePerTick: CGFloat = 4

    /// One physics tick. Computes forces (Fruchterman-Reingold), accumulates
    /// them into per-node velocities (with friction), and integrates position
    /// from velocity. Dragging is handled at the `LayoutEngine` level (the
    /// engine skips this method entirely while a drag is active).
    func advance(
        graph: GraphSnapshot,
        positions: [UUID: CGPoint],
        velocities: [UUID: CGPoint],
        alpha: Double
    ) -> (positions: [UUID: CGPoint], velocities: [UUID: CGPoint]) {
        guard !graph.nodes.isEmpty else { return (positions, velocities) }
        let nodeCount = graph.nodes.count
        let k = idealEdgeLength
        let alphaCG = CGFloat(alpha)

        var positions = positions
        var velocities = velocities
        var displacements: [UUID: CGPoint] = Dictionary(
            uniqueKeysWithValues: graph.nodes.map { ($0.id, .zero) }
        )

        // Repulsion (inverse-square so each node mainly feels its neighbors).
        for i in 0..<nodeCount {
            let nodeI = graph.nodes[i]
            guard let posI = positions[nodeI.id] else { continue }
            for j in (i + 1)..<nodeCount {
                let nodeJ = graph.nodes[j]
                guard let posJ = positions[nodeJ.id] else { continue }
                let dx = posI.x - posJ.x
                let dy = posI.y - posJ.y
                let trueDist = max(sqrt(dx * dx + dy * dy), 1)
                let dist = max(trueDist, minRepulsionDistance)
                let force = repulsionConstant / (dist * dist)
                let unitX = dx / trueDist
                let unitY = dy / trueDist
                displacements[nodeI.id]?.x += unitX * force
                displacements[nodeI.id]?.y += unitY * force
                displacements[nodeJ.id]?.x -= unitX * force
                displacements[nodeJ.id]?.y -= unitY * force
            }
        }

        // Attraction — edges as springs.
        for edge in graph.edges {
            guard let posU = positions[edge.sourceID],
                  let posV = positions[edge.targetID] else { continue }
            let dx = posU.x - posV.x
            let dy = posU.y - posV.y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let force = (dist * dist) / k
            let unitX = dx / dist
            let unitY = dy / dist
            displacements[edge.sourceID]?.x -= unitX * force
            displacements[edge.sourceID]?.y -= unitY * force
            displacements[edge.targetID]?.x += unitX * force
            displacements[edge.targetID]?.y += unitY * force
        }

        // Category clustering — gentle Hooke pull between nodes that share at
        // least one category, per ADR-0019 / ADR-0023.
        let nodeCategoryIDs: [UUID: Set<UUID>] = Dictionary(
            uniqueKeysWithValues: graph.nodes.map { node in
                (node.id, Set(node.categories.map { $0.id }))
            }
        )
        for i in 0..<nodeCount {
            let nodeI = graph.nodes[i]
            guard let categoriesI = nodeCategoryIDs[nodeI.id], !categoriesI.isEmpty else { continue }
            guard let posI = positions[nodeI.id] else { continue }
            for j in (i + 1)..<nodeCount {
                let nodeJ = graph.nodes[j]
                guard let categoriesJ = nodeCategoryIDs[nodeJ.id], !categoriesJ.isEmpty else { continue }
                if categoriesI.isDisjoint(with: categoriesJ) { continue }
                guard let posJ = positions[nodeJ.id] else { continue }
                let dx = posI.x - posJ.x
                let dy = posI.y - posJ.y
                let dist = max(sqrt(dx * dx + dy * dy), 1)
                let force = dist * categoryClusterStrength
                let unitX = dx / dist
                let unitY = dy / dist
                displacements[nodeI.id]?.x -= unitX * force
                displacements[nodeI.id]?.y -= unitY * force
                displacements[nodeJ.id]?.x += unitX * force
                displacements[nodeJ.id]?.y += unitY * force
            }
        }

        // Gentle gravity toward the world origin.
        for node in graph.nodes {
            guard let pos = positions[node.id] else { continue }
            displacements[node.id]?.x -= pos.x * gravityStrength
            displacements[node.id]?.y -= pos.y * gravityStrength
        }

        // Integrate: cap force magnitude → accumulate into velocity (with
        // friction) → step position by velocity. Velocity carries momentum
        // across ticks but decays, which damps oscillation around equilibrium.
        for node in graph.nodes {
            guard let pos = positions[node.id], let disp = displacements[node.id] else { continue }
            let dispMag = max(sqrt(disp.x * disp.x + disp.y * disp.y), 0.001)
            let limited = min(dispMag, maxForcePerTick)
            let forceX = (disp.x / dispMag) * limited
            let forceY = (disp.y / dispMag) * limited

            var velocity = velocities[node.id] ?? .zero
            velocity.x = velocity.x * (1 - velocityDecay) + forceX * alphaCG
            velocity.y = velocity.y * (1 - velocityDecay) + forceY * alphaCG

            let newPos = CGPoint(x: pos.x + velocity.x, y: pos.y + velocity.y)
            positions[node.id] = newPos
            velocities[node.id] = velocity
        }

        return (positions, velocities)
    }

    /// Establish initial positions for any node that doesn't already have one.
    /// Existing positions are preserved (so a graph addition doesn't scramble
    /// the layout). New nodes spawn around `seedOrigin` (canvas-center coords)
    /// so they land where the user is currently looking.
    /// Called by `LayoutEngine` on graph change.
    func seedPositions(
        graph: GraphSnapshot,
        previousPositions: [UUID: CGPoint],
        seedOrigin: CGPoint = .zero
    ) -> [UUID: CGPoint] {
        var positions: [UUID: CGPoint] = [:]
        let knownIDs = Set(graph.nodes.map { $0.id })
        for (id, pos) in previousPositions where knownIDs.contains(id) {
            positions[id] = pos
        }
        for node in graph.nodes where positions[node.id] == nil {
            let hash = abs(node.id.hashValue)
            let angle = CGFloat(hash % 1000) / 1000.0 * 2 * .pi
            let radius = CGFloat(20 + (hash % 60))
            positions[node.id] = CGPoint(
                x: seedOrigin.x + cos(angle) * radius,
                y: seedOrigin.y + sin(angle) * radius
            )
        }
        return positions
    }
}
