import Foundation
import CoreGraphics

struct ForceDirectedLayout: LayoutStrategy {
    let name = "Force-directed"

    private let iterations = 60
    private let repulsionConstant: CGFloat = 1_800_000
    private let minRepulsionDistance: CGFloat = 25
    private let idealEdgeLength: CGFloat = 100
    private let gravityStrength: CGFloat = 0.15
    private let initialTemperature: CGFloat = 50
    private let coolingFactor: CGFloat = 0.93
    private let safetyRadius: CGFloat = 600

    func compute(graph: GraphSnapshot, previousPositions: [UUID: CGPoint]) -> [UUID: CGPoint] {
        guard !graph.nodes.isEmpty else { return [:] }
        let nodeCount = graph.nodes.count
        let k = idealEdgeLength

        var positions = seedPositions(graph: graph, previousPositions: previousPositions)
        var temperature = initialTemperature

        for _ in 0..<iterations {
            var displacements: [UUID: CGPoint] = [:]
            for node in graph.nodes {
                displacements[node.id] = .zero
            }

            // Repulsion using inverse-square (Coulomb-style). Falls off fast with
            // distance so each node mainly feels its neighbors, not the whole graph
            // — this is what gives the layout an organic Obsidian-like spread
            // instead of every node piling on a perimeter circle.
            for i in 0..<nodeCount {
                let nodeI = graph.nodes[i]
                guard let posI = positions[nodeI.id] else { continue }
                for j in (i + 1)..<nodeCount {
                    let nodeJ = graph.nodes[j]
                    guard let posJ = positions[nodeJ.id] else { continue }
                    let dx = posI.x - posJ.x
                    let dy = posI.y - posJ.y
                    let trueDistance = max(sqrt(dx * dx + dy * dy), 1)
                    // Floor the distance used in the force calc so very-close pairs
                    // don't blow up; they still move apart but don't oscillate wildly.
                    let distance = max(trueDistance, minRepulsionDistance)
                    let force = repulsionConstant / (distance * distance)
                    let unitX = dx / trueDistance
                    let unitY = dy / trueDistance
                    displacements[nodeI.id]?.x += unitX * force
                    displacements[nodeI.id]?.y += unitY * force
                    displacements[nodeJ.id]?.x -= unitX * force
                    displacements[nodeJ.id]?.y -= unitY * force
                }
            }

            // Attraction (edges as springs).
            for edge in graph.edges {
                guard let posU = positions[edge.sourceID],
                      let posV = positions[edge.targetID] else { continue }
                let dx = posU.x - posV.x
                let dy = posU.y - posV.y
                let distance = max(sqrt(dx * dx + dy * dy), 1)
                let force = (distance * distance) / k
                let unitX = dx / distance
                let unitY = dy / distance
                displacements[edge.sourceID]?.x -= unitX * force
                displacements[edge.sourceID]?.y -= unitY * force
                displacements[edge.targetID]?.x += unitX * force
                displacements[edge.targetID]?.y += unitY * force
            }

            // Gentle gravity toward origin.
            for node in graph.nodes {
                guard let pos = positions[node.id] else { continue }
                displacements[node.id]?.x -= pos.x * gravityStrength
                displacements[node.id]?.y -= pos.y * gravityStrength
            }

            // Apply with temperature cap and a safety-radius backstop.
            for node in graph.nodes {
                guard let pos = positions[node.id], let disp = displacements[node.id] else { continue }
                let dispMag = max(sqrt(disp.x * disp.x + disp.y * disp.y), 0.001)
                let limited = min(dispMag, temperature)
                var newPos = CGPoint(
                    x: pos.x + (disp.x / dispMag) * limited,
                    y: pos.y + (disp.y / dispMag) * limited
                )
                let mag = sqrt(newPos.x * newPos.x + newPos.y * newPos.y)
                if mag > safetyRadius {
                    let scale = safetyRadius / mag
                    newPos = CGPoint(x: newPos.x * scale, y: newPos.y * scale)
                }
                positions[node.id] = newPos
            }

            temperature *= coolingFactor
        }

        return positions
    }

    /// Carry over positions for nodes that still exist; seed new nodes with
    /// pseudo-random offsets derived from their UUID hash so the initial state
    /// breaks symmetry and the simulation doesn't settle on a perfect circle.
    private func seedPositions(graph: GraphSnapshot, previousPositions: [UUID: CGPoint]) -> [UUID: CGPoint] {
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
                x: cos(angle) * radius,
                y: sin(angle) * radius
            )
        }
        return positions
    }
}
