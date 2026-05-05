import Foundation
import CoreGraphics

/// Per-cell physics simulator. Takes a set of nodes already inside (or
/// near-inside) a `Region` polygon and runs a bounded ripple — mutual
/// repulsion between members + a soft wall force keeping them inside the
/// polygon — until the system settles. Stateless: each call is a complete
/// simulation start-to-finish.
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
/// Settling: alpha starts at 1.0 and decays each iteration. The loop exits
/// when either `iterations` runs out or alpha drops below
/// `alphaThreshold`. Velocity carries momentum across iterations with
/// friction.
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

    /// Run the simulation to completion (or until alpha decays below
    /// threshold). Returns the final settled positions per node ID.
    func ripple(
        nodes: [(id: UUID, position: CGPoint, radius: CGFloat)],
        in region: Region,
        fixedNodeID: UUID? = nil
    ) -> [UUID: CGPoint] {
        guard !nodes.isEmpty else { return [:] }
        let count = nodes.count

        // Hoist into ordinal-indexed arrays for the inner pair loop —
        // dictionary lookups would dominate the per-tick budget at any
        // realistic cell size.
        var pos = [CGPoint]()
        var vel = [CGPoint](repeating: .zero, count: count)
        let rad = nodes.map { $0.radius }
        let ids = nodes.map { $0.id }
        pos.reserveCapacity(count)
        for n in nodes { pos.append(n.position) }

        let fixedIndex = fixedNodeID.flatMap { id in ids.firstIndex(of: id) }
        let polygon = region.polygon

        var alpha = 1.0
        for _ in 0..<iterations {
            if alpha < alphaThreshold { break }
            let alphaCG = CGFloat(alpha)

            var disp = [CGPoint](repeating: .zero, count: count)

            // Mutual repulsion (inverse-square). O(N²) per cell — N is
            // small (typically 3–15) so this is comfortably cheap.
            for i in 0..<count {
                for j in (i + 1)..<count {
                    let dx = pos[i].x - pos[j].x
                    let dy = pos[i].y - pos[j].y
                    let d2 = max(dx * dx + dy * dy, 1)
                    let d = sqrt(d2)
                    let f = repulsionStrength / d2
                    let fx = dx / d * f
                    let fy = dy / d * f
                    disp[i].x += fx; disp[i].y += fy
                    disp[j].x -= fx; disp[j].y -= fy
                }
            }

            // Wall repulsion. For each node, walk the cell's edges; when
            // the node is closer than `wallRange + radius` to an edge,
            // accumulate a force that ramps from `wallStrength` at the
            // edge to zero at the range boundary, directed away from the
            // edge.
            for i in 0..<count {
                let r = rad[i]
                let activationRange = wallRange + r
                for ei in 0..<polygon.count {
                    let p1 = polygon[ei]
                    let p2 = polygon[(ei + 1) % polygon.count]
                    let near = nearestPointOnSegment(pos[i], p1, p2)
                    let dx = pos[i].x - near.x
                    let dy = pos[i].y - near.y
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

            // Integrate. Velocity carries momentum with friction; cap
            // per-tick step to avoid blow-ups at very-tight initial pairs.
            for i in 0..<count {
                if i == fixedIndex { continue }
                vel[i].x = vel[i].x * (1 - velocityDecay) + disp[i].x * alphaCG
                vel[i].y = vel[i].y * (1 - velocityDecay) + disp[i].y * alphaCG
                let mag = sqrt(vel[i].x * vel[i].x + vel[i].y * vel[i].y)
                if mag > maxStepPerTick {
                    let scale = maxStepPerTick / mag
                    vel[i].x *= scale
                    vel[i].y *= scale
                }
                pos[i].x += vel[i].x
                pos[i].y += vel[i].y
            }

            alpha *= alphaDecay
        }

        var result: [UUID: CGPoint] = [:]
        result.reserveCapacity(count)
        for i in 0..<count {
            result[ids[i]] = pos[i]
        }
        return result
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
