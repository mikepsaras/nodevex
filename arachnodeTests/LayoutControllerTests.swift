import Testing
import SwiftData
import CoreGraphics
import Foundation
@testable import arachnode

@Suite("LayoutController")
@MainActor
struct LayoutControllerTests {
    private let bounds = CGRect(x: -500, y: -500, width: 1000, height: 1000)
    private let controller = LayoutController()

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Node.self, Edge.self, arachnode.Category.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeNode(
        _ context: ModelContext,
        name: String,
        value: Double = 0,
        categories: [arachnode.Category] = []
    ) -> Node {
        let n = Node(name: name, value: value)
        context.insert(n)
        n.categories = categories
        return n
    }

    @Test("empty graph → empty result")
    func emptyGraph() {
        let result = controller.computeLayout(
            graph: GraphSnapshot(nodes: [], edges: [], categories: []),
            sizing: .fixed,
            bounds: bounds
        )
        #expect(result.positions.isEmpty)
        #expect(result.regions.isEmpty)
    }

    @Test("single node → positioned at its region's centroid")
    func singleNodeAtCentroid() throws {
        let context = try makeContext()
        let n = makeNode(context, name: "A")
        let graph = GraphSnapshot(nodes: [n], edges: [], categories: [])
        let result = controller.computeLayout(
            graph: graph,
            sizing: .fixed,
            bounds: bounds
        )

        // 1 node placed; partition produces 7 regions (uncategorized +
        // 6 phantom outer slots — the default config).
        #expect(result.positions.count == 1)
        let region = result.regions[.uncategorized]!
        let pos = result.positions[n.id]!
        let centroid = region.centroid
        #expect(abs(pos.x - centroid.x) < 1e-3)
        #expect(abs(pos.y - centroid.y) < 1e-3)
    }

    @Test("every node in the graph gets a position")
    func allNodesPositioned() throws {
        let context = try makeContext()
        let cat = arachnode.Category(name: "Cat"); context.insert(cat)
        var nodes: [Node] = []
        for i in 0..<10 {
            nodes.append(makeNode(context, name: "n\(i)", categories: [cat]))
        }
        let graph = GraphSnapshot(nodes: nodes, edges: [], categories: [cat])
        let result = controller.computeLayout(
            graph: graph,
            sizing: .fixed,
            bounds: bounds
        )
        #expect(result.positions.count == 10)
        for n in nodes {
            #expect(result.positions[n.id] != nil)
        }
    }

    @Test("packed positions don't overlap")
    func packedPositionsNoOverlap() throws {
        let context = try makeContext()
        let cat = arachnode.Category(name: "Cat"); context.insert(cat)
        var nodes: [Node] = []
        for _ in 0..<8 {
            nodes.append(makeNode(context, name: "n", categories: [cat]))
        }
        let graph = GraphSnapshot(nodes: nodes, edges: [], categories: [cat])
        let result = controller.computeLayout(
            graph: graph,
            sizing: .fixed,
            bounds: bounds
        )

        let radius = NodeSizingMode.defaultRadius
        let positions = nodes.compactMap { result.positions[$0.id] }
        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                let dx = positions[i].x - positions[j].x
                let dy = positions[i].y - positions[j].y
                let dist = sqrt(dx * dx + dy * dy)
                #expect(dist >= 2 * radius - 1e-3)
            }
        }
    }

    @Test("multi-category node lands inside the combination cell")
    func multiCategoryNodeInsideCombinationRegion() throws {
        let context = try makeContext()
        let catA = arachnode.Category(name: "A"); context.insert(catA)
        let catB = arachnode.Category(name: "B"); context.insert(catB)
        // Need nodes in single-category cells too so the partitioner has
        // anchor positions for both A and B; the combination seed sits at
        // the centroid of those.
        let nA = makeNode(context, name: "nA", categories: [catA])
        let nB = makeNode(context, name: "nB", categories: [catB])
        let nAB = makeNode(context, name: "nAB", categories: [catA, catB])
        let graph = GraphSnapshot(
            nodes: [nA, nB, nAB],
            edges: [],
            categories: [catA, catB]
        )
        let result = controller.computeLayout(
            graph: graph,
            sizing: .fixed,
            bounds: bounds
        )

        guard let combinationRegion = result.regions[.combination([catA.id, catB.id])] else {
            Issue.record("expected combination region")
            return
        }
        guard let pos = result.positions[nAB.id] else {
            Issue.record("expected position for multi-category node")
            return
        }
        #expect(combinationRegion.contains(pos))
    }

    @Test("scaledByValue sizing produces different radii for different values")
    func valueSizedNodes() throws {
        let context = try makeContext()
        let cat = arachnode.Category(name: "Cat"); context.insert(cat)
        let small = makeNode(context, name: "small", value: 0.0, categories: [cat])
        let big = makeNode(context, name: "big", value: 1.0, categories: [cat])
        let graph = GraphSnapshot(
            nodes: [small, big],
            edges: [],
            categories: [cat]
        )
        let result = controller.computeLayout(
            graph: graph,
            sizing: .scaledByValue,
            bounds: bounds
        )
        // Both nodes positioned. Verify they don't overlap given their
        // value-scaled radii.
        let posSmall = result.positions[small.id]!
        let posBig = result.positions[big.id]!
        let dx = posSmall.x - posBig.x
        let dy = posSmall.y - posBig.y
        let dist = sqrt(dx * dx + dy * dy)
        let rSmall = NodeSizingMode.scaledByValue.radius(forValue: 0.0)
        let rBig = NodeSizingMode.scaledByValue.radius(forValue: 1.0)
        #expect(dist >= rSmall + rBig - 1e-3)
        #expect(rSmall < rBig)  // sanity check the sizing
    }

    @Test("stranded initial positions outside the cell are silently ignored")
    func computeLayoutIgnoresStrandedInitialPositions() throws {
        let context = try makeContext()
        let cat = arachnode.Category(name: "Cat"); context.insert(cat)
        let node = makeNode(context, name: "n", categories: [cat])
        let graph = GraphSnapshot(nodes: [node], edges: [], categories: [cat])

        // Pretend the node had a previous position way outside any
        // reasonable cell — e.g., it migrated from a totally different
        // cell that's since been removed.
        let stranded: [UUID: CGPoint] = [
            node.id: CGPoint(x: 100_000, y: 100_000)
        ]

        let result = controller.computeLayout(
            graph: graph,
            sizing: .fixed,
            bounds: bounds,
            initialPositions: stranded
        )

        // Final position must be inside the assigned cell, even though
        // `initialPositions` placed it far away. Without the fallback to
        // the packer's choice, the ripple's wall force can't recover
        // stranded inputs and they'd float "regardless of voronoi cells"
        // until dragged.
        let region = result.regions[.single(cat.id)]!
        let pos = result.positions[node.id]!
        #expect(region.contains(pos))
    }

    @Test("layout is deterministic — same graph + bounds produce same positions twice")
    func deterministic() throws {
        let context = try makeContext()
        let catA = arachnode.Category(name: "A"); context.insert(catA)
        let catB = arachnode.Category(name: "B"); context.insert(catB)
        var nodes: [Node] = []
        for _ in 0..<5 { nodes.append(makeNode(context, name: "a", categories: [catA])) }
        for _ in 0..<5 { nodes.append(makeNode(context, name: "b", categories: [catB])) }
        let graph = GraphSnapshot(
            nodes: nodes,
            edges: [],
            categories: [catA, catB]
        )
        let r1 = controller.computeLayout(graph: graph, sizing: .fixed, bounds: bounds)
        let r2 = controller.computeLayout(graph: graph, sizing: .fixed, bounds: bounds)
        for n in nodes {
            #expect(r1.positions[n.id] == r2.positions[n.id])
        }
    }
}
