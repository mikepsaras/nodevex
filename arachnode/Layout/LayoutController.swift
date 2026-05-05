import Foundation
import CoreGraphics

/// Top-level layout pipeline orchestrator. Two synchronous, deterministic
/// stages — same graph + same bounds always produces the same `LayoutResult`:
///
/// 1. **Partition** (`RegionPartitioner`) divides the layout bounds among
///    the `CategoryKey`s actually present in the graph.
/// 2. **Pack** (`CirclePacker`) places nodes tangent at the centroid of
///    each cell.
///
/// Nodes settle at the packer's tight tangent cluster at the cell
/// centroid. No spreading or fill-the-cell behavior — manual drag is the
/// way to reposition nodes within their cell. The canvas tweens between
/// successive `LayoutResult`s for visual continuity on graph changes.
final class LayoutController {
    private let partitioner: RegionPartitioner
    private let packer: CirclePacker

    init(
        partitioner: RegionPartitioner = VoronoiPartitioner(),
        packer: CirclePacker = FrontChainPacker()
    ) {
        self.partitioner = partitioner
        self.packer = packer
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

        // 3. Per-cell pack. Each cell's nodes are placed tangent at the
        //    cell centroid — that's where new nodes spawn. Existing
        //    positions (from `initialPositions`) are preserved when still
        //    inside the node's current cell, so a node that's been
        //    manually dragged keeps its placement across graph mutations.
        //    A node that migrated to a different cell (category change)
        //    snaps to the new cell's packer position.
        var positions: [UUID: CGPoint] = [:]
        positions.reserveCapacity(graph.nodes.count)
        for (key, nodes) in nodesByKey {
            guard let region = regions[key] else { continue }
            let packed = packer.pack(nodes: nodes, in: region)
            for node in nodes {
                let proposed = initialPositions[node.id] ?? packed[node.id] ?? region.centroid
                let pos = region.contains(proposed)
                    ? proposed
                    : (packed[node.id] ?? region.centroid)
                positions[node.id] = pos
            }
        }

        return LayoutResult(positions: positions, radii: radii, regions: regions)
    }
}
