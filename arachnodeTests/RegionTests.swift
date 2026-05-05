import Testing
import CoreGraphics
@testable import arachnode

@Suite("Region")
@MainActor
struct RegionTests {
    private let unitSquare = Region(polygon: [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 1, y: 0),
        CGPoint(x: 1, y: 1),
        CGPoint(x: 0, y: 1)
    ])

    @Test("area of a unit square is 1")
    func unitSquareArea() {
        #expect(abs(unitSquare.area - 1.0) < 1e-9)
    }

    @Test("centroid of a unit square is its geometric center")
    func unitSquareCentroid() {
        let c = unitSquare.centroid
        #expect(abs(c.x - 0.5) < 1e-9)
        #expect(abs(c.y - 0.5) < 1e-9)
    }

    @Test("contains: interior point")
    func containsInside() {
        #expect(unitSquare.contains(CGPoint(x: 0.5, y: 0.5)))
    }

    @Test("contains: exterior points")
    func containsOutside() {
        #expect(!unitSquare.contains(CGPoint(x: -0.1, y: 0.5)))
        #expect(!unitSquare.contains(CGPoint(x: 0.5, y: 1.5)))
        #expect(!unitSquare.contains(CGPoint(x: 5, y: 5)))
    }

    @Test("distanceFromBoundary: center of unit square is 0.5")
    func distanceFromBoundaryCenter() {
        let d = unitSquare.distanceFromBoundary(to: CGPoint(x: 0.5, y: 0.5))
        #expect(abs(d - 0.5) < 1e-9)
    }

    @Test("distanceFromBoundary: near a corner is small")
    func distanceFromBoundaryCorner() {
        let d = unitSquare.distanceFromBoundary(to: CGPoint(x: 0.05, y: 0.05))
        #expect(abs(d - 0.05) < 1e-9)
    }

    @Test("circle fits when radius is smaller than the inscribed radius")
    func circleFits() {
        let big = Region(polygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ])
        #expect(big.contains(circle: CGPoint(x: 5, y: 5), radius: 4))
    }

    @Test("circle does not fit when radius exceeds inscribed radius")
    func circleDoesntFit() {
        let big = Region(polygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10)
        ])
        // Inscribed radius of a 10×10 square is 5; radius 6 must fail.
        #expect(!big.contains(circle: CGPoint(x: 5, y: 5), radius: 6))
    }

    @Test("circle does not fit when its center is outside the polygon")
    func circleOutside() {
        #expect(!unitSquare.contains(circle: CGPoint(x: 5, y: 5), radius: 0.1))
    }

    @Test("triangle: area, centroid, containment match standard formulas")
    func triangleProperties() {
        // Right triangle (0,0)-(4,0)-(0,3) → area 6, centroid (4/3, 1).
        let t = Region(polygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 4, y: 0),
            CGPoint(x: 0, y: 3)
        ])
        #expect(abs(t.area - 6) < 1e-9)
        #expect(abs(t.centroid.x - 4.0/3.0) < 1e-9)
        #expect(abs(t.centroid.y - 1) < 1e-9)
        #expect(t.contains(CGPoint(x: 1, y: 1)))
        #expect(!t.contains(CGPoint(x: 3, y: 3)))
    }

    @Test("area is winding-independent")
    func areaWindingIndependent() {
        // CCW square
        let ccw = Region(polygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 2, y: 0),
            CGPoint(x: 2, y: 2),
            CGPoint(x: 0, y: 2)
        ])
        // CW square
        let cw = Region(polygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 0, y: 2),
            CGPoint(x: 2, y: 2),
            CGPoint(x: 2, y: 0)
        ])
        #expect(abs(ccw.area - cw.area) < 1e-9)
    }

    @Test("boundingRect tightly bounds the polygon")
    func boundingRect() {
        let r = Region(polygon: [
            CGPoint(x: -1, y: 2),
            CGPoint(x: 5, y: 0),
            CGPoint(x: 3, y: 7)
        ])
        let bb = r.boundingRect
        #expect(abs(bb.minX - (-1)) < 1e-9)
        #expect(abs(bb.minY - 0) < 1e-9)
        #expect(abs(bb.maxX - 5) < 1e-9)
        #expect(abs(bb.maxY - 7) < 1e-9)
    }

    @Test("degenerate polygon (fewer than 3 vertices) → zero area, no containment")
    func degenerate() {
        let twoPoints = Region(polygon: [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 1, y: 1)
        ])
        #expect(twoPoints.area == 0)
        #expect(!twoPoints.contains(CGPoint(x: 0.5, y: 0.5)))
    }
}
