import Foundation
import CoreGraphics

/// Top-level layout pipeline orchestrator. Three stages, all synchronous
/// and deterministic — same graph + same bounds always produces the same
/// `LayoutResult`:
///
/// 1. **Partition** (`RegionPartitioner`) divides the layout bounds among
///    the `CategoryKey`s actually present in the graph.
/// 2. **Pack** (`CirclePacker`) places nodes tangent at the centroid of
///    each cell — produces a tight cluster.
/// 3. **Ripple** (`CellRippleSimulator`) spreads each cluster out within
///    its cell using mutual repulsion + soft wall force, so nodes fill
///    the cell instead of clumping at the centroid.
///
/// All three stages are typed so an alternate implementation (weighted vs
/// unweighted partition, different packer, custom ripple parameters) can
/// be swapped in via `init(partitioner:packer:rippler:)` without touching
/// call sites.
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

        // 3. Pack each bucket inside its region (tight cluster at centroid),
        //    then ripple to spread the cluster out across the cell. The
        //    pack→ripple pair turns "tight clump in the middle" into "spread
        //    distribution filling the cell."
        //
        //    Nodes whose key didn't get a region (e.g. partitioner squeezed
        //    it out) are silently dropped from positions — the renderer
        //    just won't draw them. With weighted partitioning this is rare.
        var positions: [UUID: CGPoint] = [:]
        positions.reserveCapacity(graph.nodes.count)
        for (key, nodes) in nodesByKey {
            guard let region = regions[key] else { continue }
            let packed = packer.pack(nodes: nodes, in: region)
            // Hand the packer's output to the ripple simulator. Each ripple
            // call is self-contained — no shared state across keys.
            let rippleInput = nodes.map { node -> (id: UUID, position: CGPoint, radius: CGFloat) in
                let pos = packed[node.id] ?? region.centroid
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
