import Foundation
import CoreGraphics

/// Power-diagram (additively-weighted Voronoi) partitioner. Given a graph
/// and a layout bounds rectangle, produces one polygonal `Region` per
/// `CategoryKey` actually represented in the graph. Cell sizes scale
/// roughly with node count: a category with 50 nodes ends up with a much
/// larger cell than one with 5.
///
/// Strategy: half-plane intersection. For each seed, start with the bounds
/// polygon and clip against the weighted bisector with every other seed.
/// What's left is that seed's cell. O(seedCount²) per partition — at
/// realistic key counts (< 50) that's trivial. Avoids the bookkeeping of
/// Bowyer-Watson Delaunay extraction entirely.
///
/// Power-diagram math: a point p is "closer to seed_i than seed_j" iff
/// pow(p, i) ≤ pow(p, j), where pow(p, s) = ‖p − s‖² − weight(s). The
/// locus pow(p, i) = pow(p, j) is a straight line perpendicular to (j − i),
/// shifted from the midpoint by (w_i − w_j) / (2·‖j − i‖) toward j. Larger
/// w_i shifts the bisector away from i, growing i's cell.
///
/// Seed positions follow a fixed-slot layout — always at least the
/// "6 around 1" honeycomb visible, even before the user creates any
/// categories:
///
/// - **Center** seed is `.uncategorized` — that's where new nodes spawn
///   before they're assigned a category.
/// - **Inner ring** has 6 slots evenly distributed by angle on a ring at
///   `innerRingFraction × min(bounds.width, bounds.height)`. Categories
///   fill these slots in `createdAt` order. Slots without a category yet
///   get phantom seeds with `.empty(slotIndex:)` keys so the cell stays
///   visible as a placeholder.
/// - **Outer rings** activate when more than 6 categories exist. Ring N
///   (N ≥ 2) has 6N slots at radius `N × innerRingRadius`. No phantoms
///   in outer rings — slots only appear when categories fill them.
/// - **Combination** seeds sit at the centroid of their constituent
///   single-category seeds — a node in {A, B} ends up in the cell wedged
///   between A's and B's cells (the "Venn middle").
///
/// Sort order for category → slot assignment is `createdAt` ascending
/// with UUID tiebreaker, so adding a new category appends to the next
/// open slot without reshuffling existing positions.
struct VoronoiPartitioner: RegionPartitioner {
    /// Inner-ring radius for single-category seeds, as a fraction of
    /// `min(bounds.width, bounds.height)`.
    private let innerRingFraction: CGFloat = 0.3

    /// Calibration constant for converting node counts to power-diagram
    /// weights. Higher = more dramatic cell size differences. Tuned so
    /// that a 10× node-count ratio produces a noticeable but not extreme
    /// area difference.
    private let weightScaleDivisor: CGFloat = 8

    func partition(graph: GraphSnapshot, bounds: CGRect) -> [CategoryKey: Region] {
        let keyCounts = countNodesByKey(graph)
        guard !keyCounts.isEmpty else { return [:] }

        let seeds = computeSeeds(
            keyCounts: keyCounts,
            categories: graph.categories,
            bounds: bounds
        )
        let boundsPolygon = polygon(for: bounds)

        var result: [CategoryKey: Region] = [:]
        for (i, seed) in seeds.enumerated() {
            // Start with the full bounds and clip against every other seed's
            // bisector. What survives is this seed's cell.
            var cell = boundsPolygon
            for (j, other) in seeds.enumerated() where j != i {
                cell = clipToHalfPlane(
                    polygon: cell,
                    keep: seed,
                    discard: other
                )
                if cell.count < 3 {
                    break  // Cell collapsed to nothing — this seed got squeezed out.
                }
            }
            if cell.count >= 3 {
                result[seed.key] = Region(polygon: cell)
            }
        }
        return result
    }

    private struct Seed {
        let key: CategoryKey
        let position: CGPoint
        let weight: CGFloat
    }

    private func countNodesByKey(_ graph: GraphSnapshot) -> [CategoryKey: Int] {
        var counts: [CategoryKey: Int] = [:]
        for node in graph.nodes {
            let ids = node.categories.map { $0.id }
            let key = CategoryKey.from(categoryIDs: ids)
            counts[key, default: 0] += 1
        }
        return counts
    }

    private func computeSeeds(
        keyCounts: [CategoryKey: Int],
        categories: [Category],
        bounds: CGRect
    ) -> [Seed] {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let baseRadius = min(bounds.width, bounds.height) * innerRingFraction

        // Sort categories by createdAt (oldest first) with UUID tiebreaker
        // so adding a new category appends to the next open outer slot
        // without reshuffling earlier ones.
        let sortedCategoryIDs: [UUID] = categories
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            .map { $0.id }

        // Inner ring has 6 fixed slots; outer rings activate as needed.
        // Slots 0–5 are inner ring; slots 6–17 are middle ring (12 slots
        // at 2× radius); slots 18–35 are outer-outer ring (18 slots at
        // 3× radius); etc. (each ring N has 6N slots at radius N × base).
        var anchorByCategory: [UUID: CGPoint] = [:]
        for (slotIdx, id) in sortedCategoryIDs.enumerated() {
            anchorByCategory[id] = outerSlotPosition(
                slotIndex: slotIdx,
                center: center,
                baseRadius: baseRadius
            )
        }

        // Phantom seeds fill empty slots in the inner ring (only) — that
        // way the canvas always shows the "6 around 1" config from the
        // start, and slots fill in as the user creates categories. Outer
        // rings are sparse: only filled slots get seeds. Guard the lower
        // bound — when category count exceeds the inner ring, the range
        // `count..<innerRingSize` would be invalid and trap.
        var phantomSlots: [(slotIndex: Int, position: CGPoint)] = []
        let innerRingSize = 6
        let firstEmptySlot = min(sortedCategoryIDs.count, innerRingSize)
        for slotIdx in firstEmptySlot..<innerRingSize {
            phantomSlots.append((
                slotIndex: slotIdx,
                position: outerSlotPosition(
                    slotIndex: slotIdx,
                    center: center,
                    baseRadius: baseRadius
                )
            ))
        }

        // Weight scale: per-node weight equals (bounds area / total nodes
        // / divisor). Empty cells (no nodes — phantom slots, brand-new
        // categories without nodes) get a baseline weight equivalent to
        // 1 node so they aren't squeezed out of the tessellation.
        let totalNodes = max(keyCounts.values.reduce(0, +), 1)
        let weightScale = bounds.width * bounds.height
            / CGFloat(totalNodes)
            / weightScaleDivisor

        @inline(__always) func weightFor(_ count: Int) -> CGFloat {
            CGFloat(max(1, count)) * weightScale
        }

        var seeds: [Seed] = []

        // Center: the uncategorized cell. Always present — that's where
        // new nodes spawn even before any categories exist.
        let uncategorizedCount = keyCounts[.uncategorized] ?? 0
        seeds.append(Seed(
            key: .uncategorized,
            position: center,
            weight: weightFor(uncategorizedCount)
        ))

        // Phantom inner-ring seeds — placeholder cells with no associated
        // category yet. They render in the renderer's neutral color.
        for phantom in phantomSlots {
            seeds.append(Seed(
                key: .empty(slotIndex: phantom.slotIndex),
                position: phantom.position,
                weight: weightFor(0)
            ))
        }

        // Single-category seeds for every category present in the graph
        // (whether or not it has any nodes — empty categories still get
        // a slot so their cell shows up immediately on creation).
        for id in sortedCategoryIDs {
            guard let position = anchorByCategory[id] else { continue }
            let count = keyCounts[.single(id)] ?? 0
            seeds.append(Seed(
                key: .single(id),
                position: position,
                weight: weightFor(count)
            ))
        }

        // Combination seeds — at the centroid of constituent single-
        // category anchors. Multi-category nodes settle in the "Venn
        // middle" between their groups.
        for (key, count) in keyCounts {
            guard case .combination(let ids) = key else { continue }
            var sumX: CGFloat = 0, sumY: CGFloat = 0, num = 0
            for id in ids {
                if let anchor = anchorByCategory[id] {
                    sumX += anchor.x
                    sumY += anchor.y
                    num += 1
                }
            }
            let position = num > 0
                ? CGPoint(x: sumX / CGFloat(num), y: sumY / CGFloat(num))
                : center
            seeds.append(Seed(
                key: key,
                position: position,
                weight: weightFor(count)
            ))
        }

        return seeds
    }

    /// Slot position on the concentric-rings layout. Slot 0–5 = inner
    /// ring at radius `baseRadius`; slots 6–17 = middle ring at `2 ×
    /// baseRadius` (12 slots); slots 18–35 = outer-outer ring at `3 ×
    /// baseRadius` (18 slots); ring N has 6N slots. Within each ring,
    /// slots are evenly distributed by angle.
    private func outerSlotPosition(
        slotIndex: Int,
        center: CGPoint,
        baseRadius: CGFloat
    ) -> CGPoint {
        var ring = 1
        var firstInRing = 0
        while slotIndex >= firstInRing + 6 * ring {
            firstInRing += 6 * ring
            ring += 1
        }
        let slotInRing = slotIndex - firstInRing
        let slotsInRing = 6 * ring
        let angle = CGFloat(slotInRing) * (2 * .pi) / CGFloat(slotsInRing)
        let radius = baseRadius * CGFloat(ring)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func polygon(for rect: CGRect) -> [CGPoint] {
        // CCW order with y-up convention.
        return [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }

    /// Clip `polygon` to the half-plane on `keep`'s side of the weighted
    /// bisector between `keep` and `discard`. Sutherland-Hodgman edge-by-
    /// edge clipping.
    ///
    /// Inside test (point closer to keep in power-distance):
    ///   pow(p, keep) ≤ pow(p, discard)
    ///   ‖p − keep‖² − w_keep ≤ ‖p − discard‖² − w_discard
    /// expands to:
    ///   2·p · (discard − keep) ≤ ‖discard‖² − ‖keep‖² + w_keep − w_discard
    /// Define the signed distance as the LHS minus the RHS — `inside ⇔ ≤ 0`.
    private func clipToHalfPlane(
        polygon: [CGPoint],
        keep: Seed,
        discard: Seed
    ) -> [CGPoint] {
        let dx = discard.position.x - keep.position.x
        let dy = discard.position.y - keep.position.y
        let dSq = dx * dx + dy * dy
        guard dSq > 1e-12 else { return polygon }  // Coincident seeds — nothing to clip.

        let rhs = (discard.position.x * discard.position.x + discard.position.y * discard.position.y)
                - (keep.position.x * keep.position.x + keep.position.y * keep.position.y)
                + (keep.weight - discard.weight)

        @inline(__always) func signedDistance(_ p: CGPoint) -> CGFloat {
            // > 0 ⇒ outside (closer to discard); ≤ 0 ⇒ inside (closer to keep).
            return 2 * (p.x * dx + p.y * dy) - rhs
        }

        let n = polygon.count
        guard n > 0 else { return [] }

        var result: [CGPoint] = []
        result.reserveCapacity(n + 1)
        for i in 0..<n {
            let prev = polygon[(i + n - 1) % n]
            let curr = polygon[i]
            let dPrev = signedDistance(prev)
            let dCurr = signedDistance(curr)
            let prevInside = dPrev <= 0
            let currInside = dCurr <= 0

            if currInside {
                if !prevInside {
                    // Edge crosses bisector going inward — emit intersection.
                    let t = dPrev / (dPrev - dCurr)
                    result.append(CGPoint(
                        x: prev.x + t * (curr.x - prev.x),
                        y: prev.y + t * (curr.y - prev.y)
                    ))
                }
                result.append(curr)
            } else if prevInside {
                // Edge crosses bisector going outward — emit intersection only.
                let t = dPrev / (dPrev - dCurr)
                result.append(CGPoint(
                    x: prev.x + t * (curr.x - prev.x),
                    y: prev.y + t * (curr.y - prev.y)
                ))
            }
        }
        return result
    }
}
