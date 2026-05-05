import Foundation
import CoreGraphics

/// Tick-based force simulation. `LayoutEngine` calls `advance(...)` every
/// frame while alpha > threshold, and `seedPositions(...)` when the graph
/// changes. This is the perturb-and-restore model: continuous physics, alpha
/// decays each tick toward 0, drag perturbs alpha back to 1.0.
///
/// Per-tick forces (folded into the displacement vector and clamped together
/// at integration):
/// - Inverse-square repulsion between all node pairs (Barnes–Hut)
/// - Edge springs (attraction proportional to distance²)
/// - Gravity toward the world origin — for **uncategorized nodes only**
///
/// Plus a post-integration step that bypasses the force-clamp budget:
/// - Categorized nodes are position-blended toward their category's fixed
///   anchor slot on a ring around the origin (Democracy-4-style ministry
///   zones — see `categoryAnchorStrength` / `anchorRadius`).
struct ForceDirectedLayout {
    private let repulsionConstant: CGFloat = 1_800_000
    private let minRepulsionDistance: CGFloat = 25
    private let idealEdgeLength: CGFloat = 100
    private let gravityStrength: CGFloat = 0.15
    /// Barnes–Hut accuracy parameter. 0 = exact (full O(n²) sum), higher =
    /// faster but coarser. d3-force defaults to 0.9; we match it.
    private let barnesHutTheta: CGFloat = 0.9
    /// Per-tick blend rate (0…1) toward each owned category's **fixed**
    /// anchor (not its floating centroid), applied as a position lerp after
    /// force integration so it doesn't share the `maxForcePerTick` clamp
    /// budget with edges and repulsion. The fixed-anchor target is what
    /// gives Democracy-4-style stationary regions: edges can yank a node
    /// sideways within their clamped share, but the next tick the blend
    /// reels it back to its category's slot — and that slot doesn't drift,
    /// so the cluster as a whole stays put. (Earlier iterations targeted the
    /// floating centroid, which itself got dragged inward by central gravity
    /// + cross-category edges, producing crescents.) Scaled by alpha so the
    /// blend dies along with the rest of the simulation. Multi-category
    /// nodes blend toward the average of their owned anchors.
    private let categoryAnchorStrength: CGFloat = 0.15
    /// Radius of the per-category anchor ring around the world origin. Each
    /// category gets a fixed slot at angle `index × 2π / count`, with index
    /// determined by sorted UUID for stability. 600pt leaves comfortable
    /// gaps between slots at typical 8-category counts (≈460pt slot
    /// separation) — wide enough that ~80pt cluster radii don't overlap.
    private let anchorRadius: CGFloat = 600
    private let velocityDecay: CGFloat = 0.4
    private let maxForcePerTick: CGFloat = 4

    /// Build the per-category anchor map. Categories are sorted by UUID so
    /// the slot mapping is stable across runs. Used by both `advance` (the
    /// blend target) and `seedPositions` (initial placement) — a node
    /// spawns at its anchor and gets blended back if forces perturb it.
    private func anchorPositions(for categories: [Category]) -> [UUID: CGPoint] {
        var result: [UUID: CGPoint] = [:]
        let sortedIDs = categories.map { $0.id }
            .sorted(by: { $0.uuidString < $1.uuidString })
        guard !sortedIDs.isEmpty else { return result }
        result.reserveCapacity(sortedIDs.count)
        let slotStep = (2 * .pi) / CGFloat(sortedIDs.count)
        for (index, id) in sortedIDs.enumerated() {
            let angle = CGFloat(index) * slotStep
            result[id] = CGPoint(
                x: cos(angle) * anchorRadius,
                y: sin(angle) * anchorRadius
            )
        }
        return result
    }

    /// One physics tick. Computes forces (Fruchterman-Reingold), accumulates
    /// them into per-node velocities (with friction), and integrates position
    /// from velocity. Dragging is handled at the `LayoutEngine` level (the
    /// engine skips this method entirely while a drag is active).
    ///
    /// Implementation note: positions/velocities/displacements are hoisted
    /// into ordinal-indexed arrays for the duration of the tick. Repulsion
    /// is O(n log n) via Barnes–Hut and the anchor-blend pass is O(n), so
    /// the per-tick budget is dominated by the integration sweep — but the
    /// hot Barnes–Hut walk still does on the order of `n × log n` position
    /// reads per tick. A `[UUID: CGPoint]` lookup costs ~50 ns; an indexed
    /// array load is a couple of ns. At 500-node stress-test scale that's
    /// the difference between butter-smooth and stutter, so the array
    /// hoisting stays.
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

        var pos = [CGPoint](); pos.reserveCapacity(nodeCount)
        var vel = [CGPoint](); vel.reserveCapacity(nodeCount)
        var idToIndex = [UUID: Int](); idToIndex.reserveCapacity(nodeCount)
        for (i, node) in graph.nodes.enumerated() {
            pos.append(positions[node.id] ?? .zero)
            vel.append(velocities[node.id] ?? .zero)
            idToIndex[node.id] = i
        }
        var disp = [CGPoint](repeating: .zero, count: nodeCount)

        // Repulsion via Barnes–Hut. Build a quadtree over current positions,
        // then for each body walk the tree: distant subtrees are summarized
        // as a single mass at their center-of-mass (cheap), nearby subtrees
        // are recursed into. Drops the inverse-square sum from O(n²) to
        // O(n log n) — the difference between smooth and stuttering past
        // ~300 nodes.
        var minX: CGFloat = .infinity, maxX: CGFloat = -.infinity
        var minY: CGFloat = .infinity, maxY: CGFloat = -.infinity
        for p in pos {
            if p.x < minX { minX = p.x }
            if p.x > maxX { maxX = p.x }
            if p.y < minY { minY = p.y }
            if p.y > maxY { maxY = p.y }
        }
        // Pad so all points sit strictly inside the root bounds and zero-
        // extent layouts (everyone at one point) still produce a valid box.
        let padding: CGFloat = 1
        let treeBounds = CGRect(
            x: minX - padding,
            y: minY - padding,
            width: max(maxX - minX, 0) + 2 * padding,
            height: max(maxY - minY, 0) + 2 * padding
        )
        let tree = Quadtree(bounds: treeBounds)
        for i in 0..<nodeCount {
            tree.insert(point: pos[i], index: i)
        }
        for i in 0..<nodeCount {
            var force = CGPoint.zero
            tree.accumulateForce(
                on: pos[i],
                excludingIndex: i,
                theta: barnesHutTheta,
                repulsionConstant: repulsionConstant,
                minDistance: minRepulsionDistance,
                force: &force
            )
            disp[i].x += force.x
            disp[i].y += force.y
        }

        // Attraction — edges as springs.
        for edge in graph.edges {
            guard let u = idToIndex[edge.sourceID],
                  let v = idToIndex[edge.targetID] else { continue }
            let dx = pos[u].x - pos[v].x
            let dy = pos[u].y - pos[v].y
            let dist = max(sqrt(dx * dx + dy * dy), 1)
            let force = (dist * dist) / k
            let unitX = dx / dist
            let unitY = dy / dist
            disp[u].x -= unitX * force
            disp[u].y -= unitY * force
            disp[v].x += unitX * force
            disp[v].y += unitY * force
        }

        let categoryAnchors = anchorPositions(for: graph.categories)
        let nodeCategoryIDs: [[UUID]] = graph.nodes.map { $0.categories.map { $0.id } }

        // Gentle gravity toward the world origin — only for uncategorized
        // nodes. Categorized nodes are anchored to their category slot via
        // the post-integration blend below, which holds them against cross-
        // category edge load. Applying central gravity to them too would
        // pull every cluster's nodes inward and produce the inward-opening
        // crescent distortion (the cluster's inner-facing nodes get yanked
        // toward origin while outer-facing nodes stay put).
        for i in 0..<nodeCount where nodeCategoryIDs[i].isEmpty {
            disp[i].x -= pos[i].x * gravityStrength
            disp[i].y -= pos[i].y * gravityStrength
        }

        // Integrate: cap force magnitude → accumulate into velocity (with
        // friction) → step position by velocity. Velocity carries momentum
        // across ticks but decays, which damps oscillation around equilibrium.
        for i in 0..<nodeCount {
            let dispMag = max(sqrt(disp[i].x * disp[i].x + disp[i].y * disp[i].y), 0.001)
            let limited = min(dispMag, maxForcePerTick)
            let forceX = (disp[i].x / dispMag) * limited
            let forceY = (disp[i].y / dispMag) * limited

            vel[i].x = vel[i].x * (1 - velocityDecay) + forceX * alphaCG
            vel[i].y = vel[i].y * (1 - velocityDecay) + forceY * alphaCG

            pos[i].x += vel[i].x
            pos[i].y += vel[i].y
        }

        // Category anchor blend (post-integration). For each categorized
        // node, lerp its position toward the average of its owned anchor
        // slots. Bypasses the force-clamp budget, so anchor cohesion holds
        // regardless of how many cross-category edges pull sideways. Multi-
        // category nodes settle on the boundary between their anchors,
        // which is the right semantics. Scaled by alpha so it dies along
        // with the rest of the sim at settle.
        let blend = categoryAnchorStrength * alphaCG
        if blend > 0 {
            for i in 0..<nodeCount {
                let cats = nodeCategoryIDs[i]
                if cats.isEmpty { continue }
                var sumX: CGFloat = 0, sumY: CGFloat = 0, owned = 0
                for catID in cats {
                    guard let a = categoryAnchors[catID] else { continue }
                    sumX += a.x
                    sumY += a.y
                    owned += 1
                }
                if owned == 0 { continue }
                let cn = CGFloat(owned)
                pos[i].x += ((sumX / cn) - pos[i].x) * blend
                pos[i].y += ((sumY / cn) - pos[i].y) * blend
            }
        }

        var newPositions = [UUID: CGPoint](); newPositions.reserveCapacity(nodeCount)
        var newVelocities = [UUID: CGPoint](); newVelocities.reserveCapacity(nodeCount)
        for (i, node) in graph.nodes.enumerated() {
            newPositions[node.id] = pos[i]
            newVelocities[node.id] = vel[i]
        }
        return (newPositions, newVelocities)
    }

    /// Establish initial positions for any node that doesn't already have one.
    /// Existing positions are preserved (so a graph addition doesn't scramble
    /// the layout). Categorized nodes spawn at their category's world-coord
    /// anchor (one slot per category, evenly spaced around a circle of
    /// radius `anchorRadius`); uncategorized nodes spawn around `seedOrigin`
    /// (the viewport center) so they land where the user is currently
    /// looking. The same anchor map is consulted by `advance` for the post-
    /// integration blend, so a node spawns at its slot and the simulation
    /// keeps it there.
    ///
    /// Note: categorized nodes ignore `seedOrigin`. The whole point of
    /// fixed slots is that each category has a stable region — placing a
    /// new categorized node at the user's current viewport would scatter
    /// the cluster instead of joining it.
    ///
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
        let categoryAnchors = anchorPositions(for: graph.categories)
        for node in graph.nodes where positions[node.id] == nil {
            let anchor: CGPoint
            if let firstCategoryID = node.categories.first?.id,
               let categoryAnchor = categoryAnchors[firstCategoryID] {
                anchor = categoryAnchor
            } else {
                anchor = seedOrigin
            }
            // Per-node jitter so two same-category siblings don't pile on
            // exactly the same point (which the quadtree would have to
            // collapse into a multi-body leaf).
            let nodeHash = abs(node.id.hashValue)
            let angle = CGFloat(nodeHash % 1000) / 1000.0 * 2 * .pi
            let radius = CGFloat(20 + (nodeHash % 60))
            positions[node.id] = CGPoint(
                x: anchor.x + cos(angle) * radius,
                y: anchor.y + sin(angle) * radius
            )
        }
        return positions
    }
}

/// Barnes–Hut spatial tree. Each node either holds a single body (leaf) or
/// summarizes its quadrant via a center-of-mass + total mass (internal). The
/// tree is rebuilt every physics tick — body positions change every frame so
/// caching wouldn't pay off, and the build is `O(n log n)` anyway.
///
/// Class-based (rather than a struct of indices into a flat array) for code
/// clarity; the per-tick allocation overhead is dwarfed by the savings on
/// the inverse-square repulsion sum it replaces.
private final class Quadtree {
    /// Hard ceiling on subdivision recursion. With 500-node stress presets
    /// and a 60 000-slot hash-based seed, near-coincident initial positions
    /// are normal — without a depth cap the tree would subdivide forever
    /// and blow the stack.
    private static let maxDepth = 40
    /// If a new body sits within this squared distance of the existing
    /// leaf body, fold them into a multi-body leaf instead of subdividing.
    /// 0.0001 ≈ 0.01pt — well below sub-pixel and below floating-point
    /// noise from the integration step.
    private static let coincidenceThresholdSquared: CGFloat = 0.0001

    let bounds: CGRect
    var centerOfMass: CGPoint = .zero
    var totalMass: Int = 0
    /// Index of the single body in this leaf, or -1 if internal or a
    /// multi-body leaf (i.e. one that hit the depth cap / coincidence
    /// guard and aggregated rather than subdividing further).
    var pointIndex: Int = -1
    /// Four children in NW, NE, SW, SE order. nil while this is a leaf.
    var children: [Quadtree]?

    init(bounds: CGRect) {
        self.bounds = bounds
    }

    func insert(point: CGPoint, index: Int, depth: Int = 0) {
        if totalMass == 0 {
            centerOfMass = point
            pointIndex = index
            totalMass = 1
            return
        }

        if children == nil {
            let dx = centerOfMass.x - point.x
            let dy = centerOfMass.y - point.y
            let separationSquared = dx * dx + dy * dy
            if separationSquared < Self.coincidenceThresholdSquared
                || depth >= Self.maxDepth {
                // Coincident or out of subdivision budget — fold the new
                // body into the leaf as part of the aggregate. We lose the
                // ability to skip it during force-walk on its own row, but
                // self-force at sub-pixel distance is bounded by
                // `minRepulsionDistance` anyway.
                let count = totalMass
                centerOfMass = CGPoint(
                    x: (centerOfMass.x * CGFloat(count) + point.x) / CGFloat(count + 1),
                    y: (centerOfMass.y * CGFloat(count) + point.y) / CGFloat(count + 1)
                )
                totalMass = count + 1
                pointIndex = -1
                return
            }

            // Was a leaf with one body; subdivide and re-place that body
            // into the appropriate quadrant before adding the new one.
            subdivide()
            let oldIndex = pointIndex
            let oldPoint = centerOfMass
            pointIndex = -1
            insertIntoChild(point: oldPoint, index: oldIndex, depth: depth)
        }

        // Update the running center-of-mass before recursing.
        let count = totalMass
        centerOfMass = CGPoint(
            x: (centerOfMass.x * CGFloat(count) + point.x) / CGFloat(count + 1),
            y: (centerOfMass.y * CGFloat(count) + point.y) / CGFloat(count + 1)
        )
        totalMass = count + 1
        insertIntoChild(point: point, index: index, depth: depth)
    }

    private func subdivide() {
        let halfW = bounds.width / 2
        let halfH = bounds.height / 2
        children = [
            Quadtree(bounds: CGRect(x: bounds.minX,         y: bounds.minY,         width: halfW, height: halfH)),
            Quadtree(bounds: CGRect(x: bounds.minX + halfW, y: bounds.minY,         width: halfW, height: halfH)),
            Quadtree(bounds: CGRect(x: bounds.minX,         y: bounds.minY + halfH, width: halfW, height: halfH)),
            Quadtree(bounds: CGRect(x: bounds.minX + halfW, y: bounds.minY + halfH, width: halfW, height: halfH)),
        ]
    }

    private func insertIntoChild(point: CGPoint, index: Int, depth: Int) {
        guard let children else { return }
        let west = point.x < bounds.midX
        let north = point.y < bounds.midY
        let i: Int
        if west && north { i = 0 }
        else if !west && north { i = 1 }
        else if west && !north { i = 2 }
        else { i = 3 }
        children[i].insert(point: point, index: index, depth: depth + 1)
    }

    /// Walk the tree applying repulsion from every body to the one at
    /// `point` (skipping itself by `excludingIndex`). When a subtree is
    /// "far enough" — its width-to-distance ratio is below `theta` — we
    /// treat its whole mass as a single point and stop recursing.
    func accumulateForce(
        on point: CGPoint,
        excludingIndex: Int,
        theta: CGFloat,
        repulsionConstant: CGFloat,
        minDistance: CGFloat,
        force: inout CGPoint
    ) {
        if totalMass == 0 { return }

        if children == nil {
            // Single-body leaves can self-skip exactly. Multi-body leaves
            // (depth-capped or coincident) lose individual identity and
            // are treated as one mass; any spurious self-contribution is
            // bounded by `minDistance`.
            if pointIndex == excludingIndex { return }
            let dx = point.x - centerOfMass.x
            let dy = point.y - centerOfMass.y
            let trueDist = max(sqrt(dx * dx + dy * dy), 1)
            let dist = max(trueDist, minDistance)
            let f = (repulsionConstant * CGFloat(totalMass)) / (dist * dist)
            force.x += (dx / trueDist) * f
            force.y += (dy / trueDist) * f
            return
        }

        let dx = point.x - centerOfMass.x
        let dy = point.y - centerOfMass.y
        let trueDist = max(sqrt(dx * dx + dy * dy), 1)
        let s = max(bounds.width, bounds.height)
        if s / trueDist < theta {
            let dist = max(trueDist, minDistance)
            let f = (repulsionConstant * CGFloat(totalMass)) / (dist * dist)
            force.x += (dx / trueDist) * f
            force.y += (dy / trueDist) * f
            return
        }

        if let children {
            for child in children {
                child.accumulateForce(
                    on: point,
                    excludingIndex: excludingIndex,
                    theta: theta,
                    repulsionConstant: repulsionConstant,
                    minDistance: minDistance,
                    force: &force
                )
            }
        }
    }
}
