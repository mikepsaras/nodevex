import Foundation
import CoreGraphics

/// A bounded polygonal region of the layout — the area allotted to one
/// `CategoryKey` by a `RegionPartitioner`. Polygons are stored as a list of
/// vertices in winding order; the area / centroid / containment helpers all
/// handle either CW or CCW winding.
///
/// `Region` is a value type with no rendering state. The canvas renderer
/// reads `polygon` and optionally fills it as a tinted background; the
/// circle packer reads `centroid` for seed placement and uses
/// `contains(circle:radius:)` to verify candidate positions.
struct Region: Equatable {
    let polygon: [CGPoint]

    /// Smallest axis-aligned rectangle containing every vertex.
    var boundingRect: CGRect {
        guard !polygon.isEmpty else { return .zero }
        var minX: CGFloat = .infinity
        var minY: CGFloat = .infinity
        var maxX: CGFloat = -.infinity
        var maxY: CGFloat = -.infinity
        for p in polygon {
            if p.x < minX { minX = p.x }
            if p.y < minY { minY = p.y }
            if p.x > maxX { maxX = p.x }
            if p.y > maxY { maxY = p.y }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Area-weighted geometric centroid via the standard polygon formula.
    /// Falls back to the mean of vertices for degenerate (zero-area) polygons.
    /// Used by the packer as the placement seed for the first circle.
    var centroid: CGPoint {
        guard polygon.count >= 3 else {
            // Degenerate — return mean of vertices, or .zero for empty.
            guard !polygon.isEmpty else { return .zero }
            let n = CGFloat(polygon.count)
            return CGPoint(
                x: polygon.reduce(0) { $0 + $1.x } / n,
                y: polygon.reduce(0) { $0 + $1.y } / n
            )
        }
        var signedArea: CGFloat = 0
        var cx: CGFloat = 0
        var cy: CGFloat = 0
        for i in 0..<polygon.count {
            let p1 = polygon[i]
            let p2 = polygon[(i + 1) % polygon.count]
            let cross = p1.x * p2.y - p2.x * p1.y
            signedArea += cross
            cx += (p1.x + p2.x) * cross
            cy += (p1.y + p2.y) * cross
        }
        signedArea /= 2
        if abs(signedArea) < 1e-9 {
            let n = CGFloat(polygon.count)
            return CGPoint(
                x: polygon.reduce(0) { $0 + $1.x } / n,
                y: polygon.reduce(0) { $0 + $1.y } / n
            )
        }
        return CGPoint(x: cx / (6 * signedArea), y: cy / (6 * signedArea))
    }

    /// Polygon area via the shoelace formula. Returns the absolute value
    /// (winding-direction independent). Zero for fewer than 3 vertices.
    var area: CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<polygon.count {
            let p1 = polygon[i]
            let p2 = polygon[(i + 1) % polygon.count]
            sum += p1.x * p2.y - p2.x * p1.y
        }
        return abs(sum) / 2
    }

    /// Even-odd ray casting test. Boundary points may return either result
    /// depending on float rounding — callers that care about boundary precision
    /// should pair with `distanceFromBoundary(to:)`.
    func contains(_ point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            // Crossing test for the horizontal ray from `point` toward +∞.
            if (pi.y > point.y) != (pj.y > point.y) {
                let xCross = (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x
                if point.x < xCross {
                    inside.toggle()
                }
            }
            j = i
        }
        return inside
    }

    /// True only if the entire circle lies inside the polygon — center inside
    /// AND every edge at least `radius` away. Used by the circle packer to
    /// validate candidate placements.
    func contains(circle center: CGPoint, radius: CGFloat) -> Bool {
        guard contains(center) else { return false }
        return distanceFromBoundary(to: center) >= radius
    }

    /// Minimum distance from `point` to any polygon edge (always non-negative,
    /// regardless of inside/outside). Pair with `contains(_:)` if the sign
    /// matters.
    func distanceFromBoundary(to point: CGPoint) -> CGFloat {
        guard polygon.count >= 2 else { return 0 }
        var minDist: CGFloat = .infinity
        for i in 0..<polygon.count {
            let p1 = polygon[i]
            let p2 = polygon[(i + 1) % polygon.count]
            let d = pointToSegmentDistance(point, p1, p2)
            if d < minDist { minDist = d }
        }
        return minDist
    }

    private func pointToSegmentDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lenSq = abx * abx + aby * aby
        if lenSq < 1e-12 {
            // Degenerate segment — measure to the single endpoint.
            let dx = p.x - a.x, dy = p.y - a.y
            return sqrt(dx * dx + dy * dy)
        }
        // Project p onto segment ab, clamp t to [0, 1].
        var t = ((p.x - a.x) * abx + (p.y - a.y) * aby) / lenSq
        t = max(0, min(1, t))
        let projX = a.x + t * abx
        let projY = a.y + t * aby
        let dx = p.x - projX, dy = p.y - projY
        return sqrt(dx * dx + dy * dy)
    }

    /// Project `point` so it sits at least `inset` away from every edge of
    /// the polygon. For a convex polygon (Voronoi cells always are), this
    /// is equivalent to clamping `point` into the polygon eroded by
    /// `inset`. Useful for drag interactions where a circle of radius `r`
    /// must stay fully inside the cell — pass `inset: r`.
    ///
    /// Iterative: each pass pushes the result inward from any edge it
    /// violates; multiple passes converge for corners where two adjacent
    /// edges are violated at once. Caps at a few passes to bound work
    /// even on degenerate input.
    func clampedToInset(_ point: CGPoint, by inset: CGFloat) -> CGPoint {
        guard polygon.count >= 3 else { return point }
        let centroid = self.centroid
        var result = point

        for _ in 0..<6 {
            var moved = false
            for i in 0..<polygon.count {
                let p1 = polygon[i]
                let p2 = polygon[(i + 1) % polygon.count]
                let edgeX = p2.x - p1.x
                let edgeY = p2.y - p1.y
                let edgeLenSq = edgeX * edgeX + edgeY * edgeY
                if edgeLenSq < 1e-9 { continue }
                let edgeLen = sqrt(edgeLenSq)
                // Inward normal: pick the perpendicular that points toward
                // the centroid (which is always inside a convex polygon).
                var nx = -edgeY / edgeLen
                var ny = edgeX / edgeLen
                let midX = (p1.x + p2.x) / 2
                let midY = (p1.y + p2.y) / 2
                if nx * (centroid.x - midX) + ny * (centroid.y - midY) < 0 {
                    nx = -nx
                    ny = -ny
                }
                // Signed inward distance from the result to this edge.
                let dist = nx * (result.x - p1.x) + ny * (result.y - p1.y)
                if dist < inset {
                    let push = inset - dist
                    result.x += nx * push
                    result.y += ny * push
                    moved = true
                }
            }
            if !moved { break }
        }
        return result
    }
}
