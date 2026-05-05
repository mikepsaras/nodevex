import Foundation
import CoreGraphics

/// Top-level layout pipeline orchestrator. Three synchronous, deterministic
/// stages — same graph + same bounds always produces the same `LayoutResult`:
///
/// 1. **Partition** (`RegionPartitioner`) divides the layout bounds among
///    the `CategoryKey`s actually present in the graph.
/// 2. **Pack** (`CirclePacker`) places nodes tangent at the centroid of
///    each cell.
/// 3. **Ripple** (`CellRippleSimulator`) spreads each cluster out within
///    its cell using mutual repulsion + soft wall force, so nodes fill
///    the cell instead of clumping at the centroid.
///
/// All three stages run synchronously to completion. The canvas reads the
/// resulting `LayoutResult` and animates the visual transition between
/// frames via a smooth tween — there's no live ripple animation. Drag
/// interactions update positions directly through a separate path
/// (`CanvasNSView.mouseDragged`), bypassing this pipeline.
final class LayoutController {
    private let partitioner: RegionPartitioner
    private let packer: CirclePacker
    private let rippler: CellRippleSimulator

    init(
        partitioner: RegionPartitioner = VoronoiPartitioner(),
        packer: CirclePacker = FrontChainPacker(),
        rippler: CellRippleSimulator = CellRippleSimulator()
    ) {
        self.partitioner = partitioner
        self.packer = packer
        self.rippler = rippler
    }

    /// Run the partition + pack + ripple pipeline for the given graph and
    /// return the settled positions. `initialPositions`, when non-empty,
    /// supplies per-node hints from the previous frame so the ripple starts
    /// from where each node was — preserving smooth continuity across
    /// graph changes. Positions in `initialPositions` that fall outside
    /// the node's current cell are silently ignored (the cell-internal
    /// wall force has a bounded activation range, so stranded inputs
    /// can't be recovered by simulation alone).
    func computeLayout(
        graph: GraphSnapshot,
        sizing: NodeSizingMode,
        bounds: CGRect,
        initialPositions: [UUID: CGPoint] = [:]
    ) -> LayoutResult {
        guard !graph.nodes.isEmpty else { return .empty }

        // 1. Partition.
        let regions = partitioner.partition(graph: graph, bounds: bounds)

        // 2. Bucket nodes by their CategoryKey, computing radii up front.
        //    Radii are returned in the LayoutResult so the renderer and
        //    hit-testing path read from the same source of truth.
        var nodesByKey: [CategoryKey: [(id: UUID, radius: CGFloat)]] = [:]
        var radii: [UUID: CGFloat] = [:]
        radii.reserveCapacity(graph.nodes.count)
        for node in graph.nodes {
            let ids = node.categories.map { $0.id }
            let key = CategoryKey.from(categoryIDs: ids)
            let radius = sizing.radius(forValue: node.value)
            nodesByKey[key, default: []].append((id: node.id, radius: radius))
            radii[node.id] = radius
        }

        // 3. Per-cell pack + sync ripple. The ripple settles each cluster
        //    so the nodes spread within their cell instead of clumping at
        //    the centroid. Runs to completion before returning — the
        //    canvas tweens between successive results, it doesn't animate
        //    the ripple itself.
        var positions: [UUID: CGPoint] = [:]
        positions.reserveCapacity(graph.nodes.count)
        for (key, nodes) in nodesByKey {
            guard let region = regions[key] else { continue }
            let packed = packer.pack(nodes: nodes, in: region)
            let rippleInput = nodes.map { node -> (id: UUID, position: CGPoint, radius: CGFloat) in
                // Smooth-continuity bias: if the node's previous position
                // is still inside its (possibly reshaped) cell, start
                // there so the new layout matches "where it was" instead
                // of snapping to the packer's reset. If the previous
                // position is outside the new cell (cell migration on
                // category edit), fall back to the packer's choice — the
                // packer places at the cell centroid, definitely inside.
                let proposed = initialPositions[node.id] ?? packed[node.id] ?? region.centroid
                let pos = region.contains(proposed)
                    ? proposed
                    : (packed[node.id] ?? region.centroid)
                return (id: node.id, position: pos, radius: node.radius)
            }
            let rippled = rippler.ripple(nodes: rippleInput, in: region)
            for (id, pos) in rippled {
                positions[id] = pos
            }
        }

        return LayoutResult(positions: positions, radii: radii, regions: regions)
    }
}
