import Foundation
import CoreGraphics

/// Per-cell physics simulator. Takes a set of nodes already inside (or
/// near-inside) a `Region` polygon and runs a bounded ripple — mutual
/// repulsion between members + a soft wall force keeping them inside the
/// polygon — until the system settles.
///
/// Two ways to use:
/// - **One-shot:** `ripple(nodes:in:fixedNodeID:)` runs to completion and
///   returns settled positions. Used by `LayoutController.computeLayout`
///   for tests and any caller that wants a deterministic snapshot.
/// - **Tick-driven:** `makeState(nodes:in:fixedNodeID:)` builds an
///   initial `CellRippleState`; the caller advances it via
///   `tick(_:)` once per frame. Used by `CanvasNSView` to drive the
///   visible ripple animation.
///
/// The forces:
/// - **Mutual repulsion** between every pair of nodes in the cell, inverse
///   square in distance. Spreads tight packings out so the cluster fills
///   its cell instead of clumping at the centroid.
/// - **Wall repulsion** for nodes within `wallRange + radius` of any cell
///   edge. Linear ramp from full strength at the edge to zero at the
///   range boundary. Keeps nodes inside their cell without hard clamping
///   (which would create stuck-on-wall artifacts).
///
/// Settling: alpha starts at 1.0 and decays each tick. The simulation is
/// considered active as long as alpha stays above `alphaThreshold`.
/// Velocity carries momentum across ticks with friction.
///
/// `fixedNodeID` lets a single node be held in place during the ripple —
/// used by the drag flow so the dragged node sits at the cursor while
/// neighbors rearrange themselves around it.
struct CellRippleSimulator {
    let iterations: Int
    let alphaDecay: Double
    let alphaThreshold: Double
    /// Per-pair repulsion coefficient. Force on each node from a neighbor
    /// at distance d is `repulsionStrength / d²`. Tuned so cells of
    /// typical size (≈300pt) settle at visibly spread-out spacings.
    let repulsionStrength: CGFloat
    /// Distance from a cell edge at which the wall force activates,
    /// added to each node's radius. Outside this range, no wall force —
    /// the node is comfortably inside the cell.
    let wallRange: CGFloat
    /// Maximum wall force magnitude (applied at the edge itself; ramps
    /// linearly to zero at the range boundary). Stronger than typical
    /// pair repulsion so containment wins reliably.
    let wallStrength: CGFloat
    let velocityDecay: CGFloat
    /// Cap on per-tick movement to avoid integrator blow-ups when the
    /// initial layout has very tight pairs.
    let maxStepPerTick: CGFloat

    init(
        iterations: Int = 120,
        alphaDecay: Double = 0.95,
        alphaThreshold: Double = 0.005,
        repulsionStrength: CGFloat = 8000,
        wallRange: CGFloat = 24,
        wallStrength: CGFloat = 1200,
        velocityDecay: CGFloat = 0.4,
        maxStepPerTick: CGFloat = 8
    ) {
        self.iterations = iterations
        self.alphaDecay = alphaDecay
        self.alphaThreshold = alphaThreshold
        self.repulsionStrength = repulsionStrength
        self.wallRange = wallRange
        self.wallStrength = wallStrength
        self.velocityDecay = velocityDecay
        self.maxStepPerTick = maxStepPerTick
    }

    /// Build initial state for a tick-driven ripple. Positions and radii
    /// are hoisted into parallel arrays once so the per-tick pair loop
    /// avoids dictionary overhead. Velocities start at zero, alpha at 1.0.
    func makeState(
        nodes: [(id: UUID, position: CGPoint, radius: CGFloat)],
        in region: Region,
        fixedNodeID: UUID? = nil
    ) -> CellRippleState {
        let ids = nodes.map { $0.id }
        let positions = nodes.map { $0.position }
        let velocities = [CGPoint](repeating: .zero, count: nodes.count)
        let radii = nodes.map { $0.radius }
        let fixedIndex = fixedNodeID.flatMap { id in ids.firstIndex(of: id) }
        return CellRippleState(
            ids: ids,
            positions: positions,
            velocities: velocities,
            radii: radii,
            region: region,
            alpha: 1.0,
            fixedIndex: fixedIndex
        )
    }

    /// Advance `state` by one tick. Returns `true` if the simulation is
    /// still active afterward (alpha above threshold), `false` once it
    /// settles. The caller should keep ticking until this returns `false`.
    @discardableResult
    func tick(_ state: inout CellRippleState) -> Bool {
        guard state.alpha > alphaThreshold else { return false }
        let count = state.positions.count
        guard count > 0 else { state.alpha = 0; return false }
        let alphaCG = CGFloat(state.alpha)
        let polygon = state.region.polygon

        var disp = [CGPoint](repeating: .zero, count: count)

        // Mutual repulsion (inverse-square). O(N²) per cell — N is small
        // (typically 3–15) so this is comfortably cheap.
        for i in 0..<count {
            for j in (i + 1)..<count {
                let dx = state.positions[i].x - state.positions[j].x
                let dy = state.positions[i].y - state.positions[j].y
                let d2 = max(dx * dx + dy * dy, 1)
                let d = sqrt(d2)
                let f = repulsionStrength / d2
                let fx = dx / d * f
                let fy = dy / d * f
                disp[i].x += fx; disp[i].y += fy
                disp[j].x -= fx; disp[j].y -= fy
            }
        }

        // Wall repulsion. For each node, walk the cell's edges; when the
        // node is closer than `wallRange + radius` to an edge, accumulate
        // a force that ramps from `wallStrength` at the edge to zero at
        // the range boundary, directed away from the edge.
        for i in 0..<count {
            let r = state.radii[i]
            let activationRange = wallRange + r
            for ei in 0..<polygon.count {
                let p1 = polygon[ei]
                let p2 = polygon[(ei + 1) % polygon.count]
                let near = nearestPointOnSegment(state.positions[i], p1, p2)
                let dx = state.positions[i].x - near.x
                let dy = state.positions[i].y - near.y
                let d2 = dx * dx + dy * dy
                let d = sqrt(max(d2, 1e-6))
                if d < activationRange {
                    let ramp = (activationRange - d) / activationRange
                    let f = wallStrength * ramp
                    disp[i].x += dx / d * f
                    disp[i].y += dy / d * f
                }
            }
        }

        // Integrate. Velocity carries momentum with friction; cap per-
        // tick step to avoid blow-ups at very-tight initial pairs. The
        // fixed node (if any) skips integration — drag pins it in place.
        for i in 0..<count {
            if i == state.fixedIndex { continue }
            state.velocities[i].x = state.velocities[i].x * (1 - velocityDecay) + disp[i].x * alphaCG
            state.velocities[i].y = state.velocities[i].y * (1 - velocityDecay) + disp[i].y * alphaCG
            let mag = sqrt(state.velocities[i].x * state.velocities[i].x + state.velocities[i].y * state.velocities[i].y)
            if mag > maxStepPerTick {
                let scale = maxStepPerTick / mag
                state.velocities[i].x *= scale
                state.velocities[i].y *= scale
            }
            state.positions[i].x += state.velocities[i].x
            state.positions[i].y += state.velocities[i].y
        }

        state.alpha *= alphaDecay
        return state.alpha > alphaThreshold
    }

    /// One-shot convenience. Builds initial state, ticks until settled or
    /// `iterations` exhausted, returns the resulting positions keyed by
    /// node ID. Used by the deterministic test path and by
    /// `LayoutController.computeLayout` (which does sync ripple to keep
    /// its public API non-streaming).
    func ripple(
        nodes: [(id: UUID, position: CGPoint, radius: CGFloat)],
        in region: Region,
        fixedNodeID: UUID? = nil
    ) -> [UUID: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        var state = makeState(nodes: nodes, in: region, fixedNodeID: fixedNodeID)
        for _ in 0..<iterations {
            if !tick(&state) { break }
        }
        return state.positionsByID
    }

    /// Closest point on segment `[a, b]` to `p`. Used for wall-force
    /// proximity checks. Standard projection formula with clamp to [0, 1].
    private func nearestPointOnSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lenSq = abx * abx + aby * aby
        if lenSq < 1e-12 { return a }  // Degenerate segment.
        var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq
        t = max(0, min(1, t))
        return CGPoint(x: a.x + t * abx, y: a.y + t * aby)
    }
}

/// Mutable state for a per-cell ripple, tickable by `CellRippleSimulator`.
/// Stored externally (typically by `CanvasNSView`) and advanced one tick
/// per animation frame until `alpha` drops below threshold.
///
/// Positions, velocities, and radii are parallel arrays indexed by the
/// same `Int` (matching the `ids` array). The pair loop in `tick(_:)`
/// reads them by ordinal index — fast — and the dict-keyed
/// `positionsByID` accessor materializes the per-frame snapshot the
/// renderer + hit-test paths consume.
struct CellRippleState {
    let ids: [UUID]
    var positions: [CGPoint]
    var velocities: [CGPoint]
    let radii: [CGFloat]
    let region: Region
    var alpha: Double
    /// Index into `ids` of a node held fixed during the ripple (the
    /// dragged node, when there is one). Pinning by index, not UUID,
    /// avoids per-tick lookup.
    var fixedIndex: Int?

    /// Snapshot of current positions keyed by UUID. Allocates a fresh
    /// dictionary — call once per frame, not per pair.
    var positionsByID: [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        result.reserveCapacity(ids.count)
        for i in 0..<ids.count {
            result[ids[i]] = positions[i]
        }
        return result
    }
}
