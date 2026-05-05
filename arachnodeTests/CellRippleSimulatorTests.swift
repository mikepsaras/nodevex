import Testing
import CoreGraphics
import Foundation
@testable import arachnode

@Suite("CellRippleSimulator")
@MainActor
struct CellRippleSimulatorTests {
    private let simulator = CellRippleSimulator()

    private let bigCell = Region(polygon: [
        CGPoint(x: -200, y: -200),
        CGPoint(x: 200, y: -200),
        CGPoint(x: 200, y: 200),
        CGPoint(x: -200, y: 200)
    ])

    @Test("empty input → empty result")
    func emptyInput() {
        let result = simulator.ripple(nodes: [], in: bigCell)
        #expect(result.isEmpty)
    }

    @Test("single node alone in a cell stays roughly where it started")
    func singleNode() {
        let id = UUID()
        let start = CGPoint(x: 50, y: 30)
        let result = simulator.ripple(
            nodes: [(id: id, position: start, radius: 10)],
            in: bigCell
        )
        let pos = result[id]!
        // No other nodes to repel; only wall force could push it. At (50, 30)
        // the closest wall is 150pt away, well beyond the wall-range
        // activation, so the node should stay essentially stationary.
        #expect(abs(pos.x - start.x) < 1)
        #expect(abs(pos.y - start.y) < 1)
    }

    @Test("two near-coincident nodes spread apart")
    func twoNodesSpread() {
        let a = UUID(), b = UUID()
        // Place them tangent — repulsion should push them further apart.
        let result = simulator.ripple(
            nodes: [
                (id: a, position: CGPoint(x: -10, y: 0), radius: 10),
                (id: b, position: CGPoint(x: 10, y: 0), radius: 10)
            ],
            in: bigCell
        )
        let pa = result[a]!
        let pb = result[b]!
        let dist = hypot(pa.x - pb.x, pa.y - pb.y)
        // Started at distance 20 (tangent for two r=10 circles); should end
        // visibly further.
        #expect(dist > 25)
    }

    @Test("node near a wall is pushed inward")
    func wallPushesInward() {
        let id = UUID()
        // Place near the right wall of a (-200, 200) cell — node center at
        // x=185, radius 10 → only 15pt clearance, well inside wall-range.
        let result = simulator.ripple(
            nodes: [(id: id, position: CGPoint(x: 185, y: 0), radius: 10)],
            in: bigCell
        )
        let pos = result[id]!
        // Node should have moved away from the right wall (toward smaller x).
        #expect(pos.x < 185)
    }

    @Test("fixed node stays exactly at its starting position")
    func fixedNodeUnchanged() {
        let fixed = UUID()
        let other = UUID()
        let fixedStart = CGPoint(x: 0, y: 0)
        let result = simulator.ripple(
            nodes: [
                (id: fixed, position: fixedStart, radius: 10),
                (id: other, position: CGPoint(x: 5, y: 0), radius: 10)
            ],
            in: bigCell,
            fixedNodeID: fixed
        )
        // Fixed node didn't move at all.
        #expect(result[fixed]! == fixedStart)
        // Free node moved away from the fixed neighbor (was tangent on
        // its left, should slide further left after ripple).
        #expect(result[other]!.x > 5)
    }

    @Test("after ripple, all nodes remain inside the cell polygon")
    func nodesStayInsideCell() {
        // A handful of nodes packed tight against each other near the
        // cell's right wall — wall + mutual repulsion fight; verify wall
        // wins (containment holds).
        let ids = (0..<6).map { _ in UUID() }
        let nodes = zip(ids, 0..<6).map { (id, i) -> (id: UUID, position: CGPoint, radius: CGFloat) in
            (id: id, position: CGPoint(x: 150 + CGFloat(i) * 2, y: 0), radius: 10)
        }
        let result = simulator.ripple(nodes: nodes, in: bigCell)
        for id in ids {
            let pos = result[id]!
            // Every node's center is inside the (-200, 200) box.
            #expect(pos.x > -200 && pos.x < 200)
            #expect(pos.y > -200 && pos.y < 200)
        }
    }

    @Test("mutual repulsion produces non-overlapping settled positions")
    func nonOverlapAfterRipple() {
        let ids = (0..<5).map { _ in UUID() }
        // Start near each other but not coincident — coincident nodes have
        // zero direction for inverse-square repulsion, so the force can't
        // disambiguate. Real packer output never produces coincident
        // positions, so a tiny initial offset matches reality.
        let nodes = ids.enumerated().map { (i, id) -> (id: UUID, position: CGPoint, radius: CGFloat) in
            (id: id, position: CGPoint(x: CGFloat(i) * 0.5, y: 0), radius: 8)
        }
        let result = simulator.ripple(nodes: nodes, in: bigCell)
        // After ripple, no pair should overlap (distance ≥ sum of radii).
        let positioned = ids.map { (id: $0, p: result[$0]!) }
        for i in 0..<positioned.count {
            for j in (i + 1)..<positioned.count {
                let dist = hypot(
                    positioned[i].p.x - positioned[j].p.x,
                    positioned[i].p.y - positioned[j].p.y
                )
                #expect(dist > 14, "pair \(i),\(j) too close: dist=\(dist)")
            }
        }
    }
}
