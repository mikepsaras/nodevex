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
/// Seed positions:
/// - **Single-category** seeds sit on an inner ring (radius 30% of
///   min(bounds.width, bounds.height)), evenly spaced by angle, sorted by
///   UUID for stability. Categorized cells dominate the central area.
/// - **Combination** seeds sit at the centroid of their constituent
///   single-category seeds — a node in {A, B} ends up in the cell wedged
///   between A's and B's cells (the "Venn middle").
/// - **Uncategorized** seed sits near the top-right corner of bounds, so
///   its cell is the peripheral wedge. Categorized cells take visual
///   priority from the center outward.
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

        let seeds = computeSeeds(keyCounts: keyCounts, bounds: bounds)
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

    private func computeSeeds(keyCounts: [CategoryKey: Int], bounds: CGRect) -> [Seed] {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let innerRadius = min(bounds.width, bounds.height) * innerRingFraction

        // Stable per-category ring slot: sort UUIDs to make the assignment
        // deterministic across runs (and across re-partitions of the same
        // graph).
        let singleCategoryIDs: [UUID] = keyCounts.keys.compactMap { key in
            if case .single(let id) = key { return id }
            return nil
        }.sorted(by: { $0.uuidString < $1.uuidString })

        var anchorByCategory: [UUID: CGPoint] = [:]
        if !singleCategoryIDs.isEmpty {
            let slotStep = (2 * .pi) / CGFloat(singleCategoryIDs.count)
            for (idx, id) in singleCategoryIDs.enumerated() {
                let angle = CGFloat(idx) * slotStep
                anchorByCategory[id] = CGPoint(
                    x: center.x + cos(angle) * innerRadius,
                    y: center.y + sin(angle) * innerRadius
                )
            }
        }

        // Weight scale: per-node weight equals (bounds area / total nodes /
        // divisor). Divisor dampens dramatic cell-size differences.
        let totalNodes = max(keyCounts.values.reduce(0, +), 1)
        let weightScale = bounds.width * bounds.height
            / CGFloat(totalNodes)
            / weightScaleDivisor

        var seeds: [Seed] = []
        seeds.reserveCapacity(keyCounts.count)
        for (key, count) in keyCounts {
            let position: CGPoint
            switch key {
            case .single(let id):
                position = anchorByCategory[id] ?? center
            case .combination(let ids):
                // Centroid of constituent single-category anchors. Multi-
                // category nodes settle in the "Venn middle" between groups.
                var sumX: CGFloat = 0, sumY: CGFloat = 0, num = 0
                for id in ids {
                    if let anchor = anchorByCategory[id] {
                        sumX += anchor.x
                        sumY += anchor.y
                        num += 1
                    }
                }
                position = num > 0
                    ? CGPoint(x: sumX / CGFloat(num), y: sumY / CGFloat(num))
                    : center
            case .uncategorized:
                // Peripheral wedge near the top-right corner of bounds.
                position = CGPoint(
                    x: bounds.maxX - bounds.width * 0.05,
                    y: bounds.maxY - bounds.height * 0.05
                )
            }
            seeds.append(Seed(
                key: key,
                position: position,
                weight: CGFloat(count) * weightScale
            ))
        }
        return seeds
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
