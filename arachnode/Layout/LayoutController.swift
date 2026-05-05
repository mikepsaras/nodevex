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

    /// Synchronous entry point — runs partition + pack + full ripple-to-
    /// settled, returns an immutable `LayoutResult`. `sizing` picks per-
    /// node radii from each node's intrinsic value; `bounds` is typically
    /// the active display's `visibleFrame.size`. Used by tests and any
    /// caller that wants a deterministic snapshot. `CanvasNSView` instead
    /// uses `prepareLayout` + per-frame `tick(_:)` so the user sees the
    /// ripple animate.
    func computeLayout(
        graph: GraphSnapshot,
        sizing: NodeSizingMode,
        bounds: CGRect
    ) -> LayoutResult {
        guard !graph.nodes.isEmpty else { return .empty }
        var live = prepareLayout(graph: graph, sizing: sizing, bounds: bounds)
        while tick(&live) { /* ripple all cells until settled */ }
        return live.snapshot
    }

    /// Build initial layout state — partition, pack, and make per-cell
    /// ripple states — but DO NOT tick. The caller is expected to drive
    /// `tick(_:)` to advance the ripple frame-by-frame.
    ///
    /// `initialPositions` lets the caller seed nodes from a previous frame
    /// so an existing node smoothly ripples from where it was rather than
    /// snapping to the packer's choice. Nodes not in `initialPositions`
    /// start at the packer's position (typically newly-added nodes).
    func prepareLayout(
        graph: GraphSnapshot,
        sizing: NodeSizingMode,
        bounds: CGRect,
        initialPositions: [UUID: CGPoint] = [:]
    ) -> LiveLayoutState {
        guard !graph.nodes.isEmpty else { return .empty }

        let regions = partitioner.partition(graph: graph, bounds: bounds)

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

        var rippleStates: [CategoryKey: CellRippleState] = [:]
        rippleStates.reserveCapacity(nodesByKey.count)
        for (key, nodes) in nodesByKey {
            guard let region = regions[key] else { continue }
            let packed = packer.pack(nodes: nodes, in: region)
            let rippleInput = nodes.map { node -> (id: UUID, position: CGPoint, radius: CGFloat) in
                // Smooth-continuity bias: if the node's previous position
                // is still inside its (possibly reshaped) cell, start
                // there so the ripple animates from "where it was" rather
                // than snapping to the packer's reset. If the previous
                // position is outside the new cell — which happens when
                // cells reshape on graph mutation, especially around
                // category changes — fall back to the packer's choice.
                //
                // The fallback matters: the ripple's wall force has a
                // bounded activation range, so a node stranded far from
                // its assigned cell can't be reeled in by the simulation
                // alone. It would just float "regardless of cells" until
                // a drag forced it back. Validate up-front instead.
                let proposed = initialPositions[node.id] ?? packed[node.id] ?? region.centroid
                let pos = region.contains(proposed)
                    ? proposed
                    : (packed[node.id] ?? region.centroid)
                return (id: node.id, position: pos, radius: node.radius)
            }
            rippleStates[key] = rippler.makeState(nodes: rippleInput, in: region)
        }

        return LiveLayoutState(
            regions: regions,
            radii: radii,
            rippleStates: rippleStates
        )
    }

    /// Advance every per-cell ripple in `state` by one tick. Returns
    /// `true` if any cell is still active afterward; `false` once all
    /// cells have settled. The caller should keep calling this on each
    /// animation frame until it returns `false`.
    @discardableResult
    func tick(_ state: inout LiveLayoutState) -> Bool {
        var anyActive = false
        for key in state.rippleStates.keys {
            // Pull, tick (mutates), put back. Dictionary modify-in-place
            // (`state.rippleStates[key]?.alpha = …`) wouldn't compose with
            // the simulator's `inout` API.
            var cellState = state.rippleStates[key]!
            if rippler.tick(&cellState) {
                anyActive = true
            }
            state.rippleStates[key] = cellState
        }
        return anyActive
    }
}

/// Mutable snapshot of an in-progress layout. Bundles the (immutable)
/// regions and radii with the (mutable) per-cell ripple states. The
/// caller advances ripple states via `LayoutController.tick(_:)` until
/// `isActive` returns `false`. Reading `positions` materializes a
/// fresh dictionary across all cells — call once per frame.
struct LiveLayoutState {
    let regions: [CategoryKey: Region]
    let radii: [UUID: CGFloat]
    var rippleStates: [CategoryKey: CellRippleState]

    static let empty = LiveLayoutState(regions: [:], radii: [:], rippleStates: [:])

    /// Aggregated current positions across every cell's ripple state.
    var positions: [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        for state in rippleStates.values {
            for i in 0..<state.ids.count {
                result[state.ids[i]] = state.positions[i]
            }
        }
        return result
    }

    /// Immutable view of the current state — typically used by tests or
    /// after the ripple has settled.
    var snapshot: LayoutResult {
        LayoutResult(positions: positions, radii: radii, regions: regions)
    }
}
