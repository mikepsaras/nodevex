import Testing
import CoreGraphics
import Foundation
@testable import arachnode

@Suite("FrontChainPacker")
@MainActor
struct FrontChainPackerTests {
    private let packer = FrontChainPacker()

    private let bigSquare = Region(polygon: [
        CGPoint(x: -100, y: -100),
        CGPoint(x: 100, y: -100),
        CGPoint(x: 100, y: 100),
        CGPoint(x: -100, y: 100)
    ])

    @Test("empty input → empty result")
    func emptyInput() {
        let result = packer.pack(nodes: [], in: bigSquare)
        #expect(result.isEmpty)
    }

    @Test("single circle is placed at the region centroid")
    func singleCircle() {
        let id = UUID()
        let result = packer.pack(nodes: [(id: id, radius: 5)], in: bigSquare)
        #expect(result.count == 1)
        let pos = result[id]!
        let centroid = bigSquare.centroid
        #expect(abs(pos.x - centroid.x) < 1e-6)
        #expect(abs(pos.y - centroid.y) < 1e-6)
    }

    @Test("two circles are tangent (distance = sum of radii)")
    func twoCirclesTangent() {
        let a = UUID(), b = UUID()
        let result = packer.pack(
            nodes: [(id: a, radius: 5), (id: b, radius: 3)],
            in: bigSquare
        )
        let pa = result[a]!
        let pb = result[b]!
        let dx = pa.x - pb.x
        let dy = pa.y - pb.y
        let dist = sqrt(dx * dx + dy * dy)
        #expect(abs(dist - 8) < 1e-3)
    }

    @Test("three equal circles form an equilateral triangle")
    func threeEqualCirclesTriangle() {
        let ids = [UUID(), UUID(), UUID()]
        let result = packer.pack(
            nodes: ids.map { (id: $0, radius: CGFloat(5)) },
            in: bigSquare
        )
        let positions = ids.map { result[$0]! }
        // All three pairwise distances should equal 2*r = 10 (tangent pairs).
        for i in 0..<3 {
            for j in (i + 1)..<3 {
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let dist = sqrt(dx * dx + dy * dy)
                #expect(abs(dist - 10) < 1e-3)
            }
        }
    }

    @Test("ten circles of varying radii produce non-overlapping placements")
    func tenCirclesNoOverlap() {
        let radii: [CGFloat] = [12, 10, 9, 8, 7, 6, 5, 4, 3, 2]
        let nodes: [(id: UUID, radius: CGFloat)] = radii.map { (id: UUID(), radius: $0) }
        let result = packer.pack(nodes: nodes, in: bigSquare)
        #expect(result.count == 10)

        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let pi = result[nodes[i].id]!
                let pj = result[nodes[j].id]!
                let dx = pi.x - pj.x
                let dy = pi.y - pj.y
                let dist = sqrt(dx * dx + dy * dy)
                let minDist = nodes[i].radius + nodes[j].radius - 1e-3
                #expect(
                    dist >= minDist,
                    "circles \(i) and \(j) overlap: dist=\(dist) needs ≥ \(minDist)"
                )
            }
        }
    }

    @Test("non-zero region centroid pins the packed cluster correctly")
    func nonZeroCentroidRegion() {
        let offsetSquare = Region(polygon: [
            CGPoint(x: 100, y: 50),
            CGPoint(x: 200, y: 50),
            CGPoint(x: 200, y: 150),
            CGPoint(x: 100, y: 150)
        ])
        let id = UUID()
        let result = packer.pack(
            nodes: [(id: id, radius: 5)],
            in: offsetSquare
        )
        // Offset square centroid is (150, 100).
        let pos = result[id]!
        #expect(abs(pos.x - 150) < 1e-6)
        #expect(abs(pos.y - 100) < 1e-6)
    }

    @Test("packed cluster's area-weighted centroid lands at the region centroid")
    func clusterCentroidAtRegionCentroid() {
        let radii: [CGFloat] = [10, 8, 6, 5, 4, 3]
        let nodes: [(id: UUID, radius: CGFloat)] = radii.map { (id: UUID(), radius: $0) }
        let result = packer.pack(nodes: nodes, in: bigSquare)
        let target = bigSquare.centroid

        // Compute area-weighted centroid of the packed result.
        var totalArea: CGFloat = 0
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        for n in nodes {
            let p = result[n.id]!
            let a = n.radius * n.radius
            totalArea += a
            sumX += p.x * a
            sumY += p.y * a
        }
        let centroid = CGPoint(x: sumX / totalArea, y: sumY / totalArea)

        #expect(abs(centroid.x - target.x) < 1e-3)
        #expect(abs(centroid.y - target.y) < 1e-3)
    }

    @Test("twenty circles still pack without overlap (stress)")
    func twentyCirclesStress() {
        var nodes: [(id: UUID, radius: CGFloat)] = []
        for i in 0..<20 {
            // Mix of radii so placements have to handle varying sizes.
            let r: CGFloat = 3 + CGFloat(i % 5) * 2
            nodes.append((id: UUID(), radius: r))
        }
        let region = Region(polygon: [
            CGPoint(x: -200, y: -200),
            CGPoint(x: 200, y: -200),
            CGPoint(x: 200, y: 200),
            CGPoint(x: -200, y: 200)
        ])
        let result = packer.pack(nodes: nodes, in: region)
        #expect(result.count == 20)

        // Spot-check pairwise non-overlap on a sample (full O(n²) checked too).
        for i in 0..<nodes.count {
            for j in (i + 1)..<nodes.count {
                let pi = result[nodes[i].id]!
                let pj = result[nodes[j].id]!
                let dx = pi.x - pj.x
                let dy = pi.y - pj.y
                let dist = sqrt(dx * dx + dy * dy)
                let minDist = nodes[i].radius + nodes[j].radius - 1e-3
                #expect(dist >= minDist)
            }
        }
    }
}
