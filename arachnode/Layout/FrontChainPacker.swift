import Foundation
import CoreGraphics

/// Front-chain circle packer — port of d3-hierarchy's pack/siblings.js.
/// Sorts circles by descending radius, places them tangent to existing
/// front-chain neighbors, walking outward. Produces dense, deterministic,
/// roughly-circular cluster packings.
///
/// Each circle's radius is inflated by `nodeSpacing` for the packing math
/// only — the returned positions are in the natural unpadded coord system,
/// so the renderer draws circles at their actual size with `2 × nodeSpacing`
/// of breathing room between them. Tangent-look-and-feel is rarely what you
/// want visually; a small gap reads as a deliberate arrangement instead of
/// a dense pile.
///
/// After packing in pack-local coordinates, the cluster is translated so
/// its area-weighted centroid aligns with the region centroid. Overflow
/// (circles extending outside the polygon) is accepted — the renderer
/// doesn't clip. With node-count-weighted partitioning that should be
/// rare; if it happens it's a visual cue that a region is undersized
/// relative to its node count.
struct FrontChainPacker: CirclePacker {
    /// Per-circle padding fraction used during packing math — each circle's
    /// radius is inflated by `radius × spacingFraction` (with a floor of
    /// `minSpacing`) before placement. Proportional spacing reads more
    /// naturally than a fixed-pixel pad: large circles get bigger gaps,
    /// small circles get smaller gaps, instead of the same absolute padding
    /// crushing the small ones and barely showing on the large ones.
    private let spacingFraction: CGFloat = 0.15
    private let minSpacing: CGFloat = 2

    func pack(
        nodes: [(id: UUID, radius: CGFloat)],
        in region: Region
    ) -> [UUID: CGPoint] {
        guard !nodes.isEmpty else { return [:] }

        // Inflate radii for packing math. Returned positions are unaffected
        // — the renderer reads positions and original radii separately, so
        // the gap appears between rendered circles.
        let originalRadii = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0.radius) })
        let inflated = nodes.map { node -> (id: UUID, radius: CGFloat) in
            let pad = max(node.radius * spacingFraction, minSpacing)
            return (id: node.id, radius: node.radius + pad)
        }
        let sorted = inflated.sorted(by: { $0.radius > $1.radius })
        let packed = packCircles(sorted)

        // Translate cluster so its area-weighted centroid (computed against
        // the original, *visible* radii) lands at the region's centroid.
        // Centering by inflated radii would put the gaps' weight in the
        // mass calculation, off-balancing the visible result for non-
        // uniform-radius packings.
        let clusterCenter = areaWeightedCentroid(of: packed, weights: originalRadii)
        let target = region.centroid
        let dx = target.x - clusterCenter.x
        let dy = target.y - clusterCenter.y

        var result: [UUID: CGPoint] = [:]
        result.reserveCapacity(packed.count)
        for circle in packed {
            result[circle.id] = CGPoint(x: circle.x + dx, y: circle.y + dy)
        }
        return result
    }

    private struct PackedCircle {
        let id: UUID
        var x: CGFloat
        var y: CGFloat
        let r: CGFloat
    }

    /// Doubly-linked list node for the active front. Holds an index into
    /// the `packed` array so we can mutate underlying positions without
    /// restructuring the chain. Reference type for the doubly-linked
    /// pointers — the chain mutates often during packing.
    private final class FrontNode {
        let index: Int
        var prev: FrontNode!
        var next: FrontNode!
        init(index: Int) { self.index = index }
    }

    private func packCircles(_ sorted: [(id: UUID, radius: CGFloat)]) -> [PackedCircle] {
        var packed: [PackedCircle] = []
        packed.reserveCapacity(sorted.count)

        // 1 circle: trivial — placed at origin.
        packed.append(PackedCircle(id: sorted[0].id, x: 0, y: 0, r: sorted[0].radius))
        if sorted.count == 1 { return packed }

        // 2 circles: tangent along x-axis.
        let r0 = packed[0].r
        let r1 = sorted[1].radius
        packed.append(PackedCircle(id: sorted[1].id, x: r0 + r1, y: 0, r: r1))
        if sorted.count == 2 { return packed }

        // 3 circles: place third tangent to the first two. Note the d3
        // convention: `place(b, a, c)` positions c on the CCW side of vector
        // a → b. At init, vector goes from circle 0 to circle 1 (rightward),
        // so circle 2 lands above the x-axis.
        var third = PackedCircle(id: sorted[2].id, x: 0, y: 0, r: sorted[2].radius)
        place(b: packed[1], a: packed[0], c: &third)
        packed.append(third)

        // Initialize front chain: 0 -> 1 -> 2 -> 0 (CCW with y-up).
        let n0 = FrontNode(index: 0)
        let n1 = FrontNode(index: 1)
        let n2 = FrontNode(index: 2)
        n0.next = n1; n1.prev = n0
        n1.next = n2; n2.prev = n1
        n2.next = n0; n0.prev = n2

        // Front-chain leading edge: a is "back", b is "front". New circles
        // place tangent to (a, b) on the outside of the cluster.
        var a = n0
        var b = n1

        var i = 3
        place_loop: while i < sorted.count {
            var newC = PackedCircle(id: sorted[i].id, x: 0, y: 0, r: sorted[i].radius)
            // Argument convention swap vs init: front-chain a maps to
            // place's b parameter, and front-chain b maps to place's a
            // parameter — that puts the new circle on the outside of the
            // current chain boundary, not inside it.
            place(b: packed[a.index], a: packed[b.index], c: &newC)

            // Walk the front looking for an existing circle that intersects
            // the candidate placement. j walks forward from b, k walks
            // backward from a; whichever side has accumulated less radius
            // walks first to balance work. If we find an intersector, drop
            // it from the front by linking its neighbors directly and retry
            // the placement at the same `i` (continue without incrementing).
            var j: FrontNode = b.next
            var k: FrontNode = a.prev
            var sj: CGFloat = packed[b.index].r
            var sk: CGFloat = packed[a.index].r

            repeat {
                if sj <= sk {
                    if intersects(packed[j.index], newC) {
                        b = j
                        a.next = b
                        b.prev = a
                        continue place_loop
                    }
                    sj += packed[j.index].r
                    j = j.next
                } else {
                    if intersects(packed[k.index], newC) {
                        a = k
                        a.next = b
                        b.prev = a
                        continue place_loop
                    }
                    sk += packed[k.index].r
                    k = k.prev
                }
            } while j !== k.next

            // No intersection — accept placement, append to packed, splice
            // a new front node between a and b.
            let newIdx = packed.count
            packed.append(newC)
            let newNode = FrontNode(index: newIdx)
            newNode.prev = a
            newNode.next = b
            a.next = newNode
            b.prev = newNode
            b = newNode

            // Choose the next leading anchor: walk the chain looking for the
            // front node closest to origin (lowest score). d3's heuristic:
            // anchor at the node whose tangent midpoint is nearest origin —
            // that's the side most starved for additional packing.
            var bestA = a
            var bestScore = score(a, packed: packed)
            var walker: FrontNode = b.next
            while walker !== b {
                let s = score(walker, packed: packed)
                if s < bestScore {
                    bestA = walker
                    bestScore = s
                }
                walker = walker.next
            }
            a = bestA
            b = a.next

            i += 1
        }

        return packed
    }

    /// Place `c` tangent to circles `a` and `b`, on the CCW side of vector
    /// a → b. Port of d3-hierarchy's place(b, a, c). The branch on `a2 > b2`
    /// picks the formulation with better numerical conditioning when the
    /// two anchor circles have very different radii.
    private func place(b: PackedCircle, a: PackedCircle, c: inout PackedCircle) {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let d2 = dx * dx + dy * dy
        if d2 < 1e-9 {
            // a and b coincide — degenerate input. Place c to the right of a.
            c.x = a.x + a.r + c.r
            c.y = a.y
            return
        }
        let a2 = (a.r + c.r) * (a.r + c.r)
        let b2 = (b.r + c.r) * (b.r + c.r)
        if a2 > b2 {
            let x = (d2 + b2 - a2) / (2 * d2)
            let y = sqrt(max(0, b2 / d2 - x * x))
            c.x = b.x - x * dx - y * dy
            c.y = b.y - x * dy + y * dx
        } else {
            let x = (d2 + a2 - b2) / (2 * d2)
            let y = sqrt(max(0, a2 / d2 - x * x))
            c.x = a.x + x * dx - y * dy
            c.y = a.y + x * dy + y * dx
        }
    }

    /// True if two circles overlap (with a tiny epsilon tolerance so
    /// numerically-tangent placements register as touching, not overlapping).
    private func intersects(_ a: PackedCircle, _ b: PackedCircle) -> Bool {
        let dr = a.r + b.r - 1e-6
        let dx = b.x - a.x
        let dy = b.y - a.y
        return dr > 0 && dr * dr > dx * dx + dy * dy
    }

    /// Squared distance from origin to the radius-weighted tangent point
    /// between this front node and its successor. d3's heuristic: lower
    /// score = closer to origin = better candidate for the next leading
    /// anchor (the chain grows outward from the densest pocket).
    private func score(_ node: FrontNode, packed: [PackedCircle]) -> CGFloat {
        let a = packed[node.index]
        let b = packed[node.next.index]
        let ab = a.r + b.r
        guard ab > 0 else { return 0 }
        let dx = (a.x * b.r + b.x * a.r) / ab
        let dy = (a.y * b.r + b.y * a.r) / ab
        return dx * dx + dy * dy
    }

    /// Area-weighted centroid using a per-id radius lookup (original, not
    /// inflated). Larger circles count proportionally more so the cluster
    /// translation balances visual mass rather than just vertex count.
    /// Falls back to `c.r` for any id missing from `weights`.
    private func areaWeightedCentroid(
        of packed: [PackedCircle],
        weights: [UUID: CGFloat]
    ) -> CGPoint {
        guard !packed.isEmpty else { return .zero }
        var totalArea: CGFloat = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for c in packed {
            let r = weights[c.id] ?? c.r
            let area = r * r  // π cancels in the weighted average
            totalArea += area
            sumX += c.x * area
            sumY += c.y * area
        }
        if totalArea < 1e-9 {
            return .zero
        }
        return CGPoint(x: sumX / totalArea, y: sumY / totalArea)
    }
}
