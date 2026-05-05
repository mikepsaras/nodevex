import Foundation
import CoreGraphics

/// Top-level layout pipeline orchestrator. Coordinates the
/// `RegionPartitioner` (divides the layout bounds among `CategoryKey`s)
/// with the `CirclePacker` (packs each region's nodes inside its polygon).
/// Synchronous, deterministic, fast — same graph + same bounds always
/// produces the same `LayoutResult`.
///
/// Both stages are protocol-typed so an alternate strategy (e.g. weighted
/// vs unweighted partition, or a different packer) can be swapped in via
/// `init(partitioner:packer:)` without touching call sites. The defaults
/// — `VoronoiPartitioner` + `FrontChainPacker` — are what the canvas wires
/// up in production.
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

    /// Compute a fresh layout for the given graph. `sizing` picks node radii
    /// from each node's intrinsic value (`NodeSizingMode.fixed` ignores the
    /// value, `.scaledByValue` ranges the radius across the configured
    /// span). `bounds` is the full layout extent — typically the active
    /// display's `visibleFrame.size` so the partition fills the screen.
    func computeLayout(
        graph: GraphSnapshot,
        sizing: NodeSizingMode,
        bounds: CGRect
    ) -> LayoutResult {
        guard !graph.nodes.isEmpty else { return .empty }

        // 1. Partition bounds into one polygon per CategoryKey actually in use.
        let regions = partitioner.partition(graph: graph, bounds: bounds)

        // 2. Bucket nodes by their CategoryKey, computing radii up front.
        //    Radii are also returned in the LayoutResult so the renderer and
        //    hit-testing path read from the same source of truth — no
        //    side-channel recomputation in CanvasNSView.
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

        // 3. Pack each bucket inside its region. Nodes whose key didn't get
        //    a region (e.g. partitioner squeezed it out) are silently dropped
        //    from the positions map — the renderer just won't draw them.
        //    With the current weighted-partition tuning this shouldn't happen.
        var positions: [UUID: CGPoint] = [:]
        positions.reserveCapacity(graph.nodes.count)
        for (key, nodes) in nodesByKey {
            guard let region = regions[key] else { continue }
            let packed = packer.pack(nodes: nodes, in: region)
            for (id, pos) in packed {
                positions[id] = pos
            }
        }

        return LayoutResult(positions: positions, radii: radii, regions: regions)
    }
}
