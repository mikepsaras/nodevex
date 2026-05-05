import Testing
import SwiftData
import CoreGraphics
import Foundation
@testable import arachnode

@Suite("VoronoiPartitioner")
@MainActor
struct VoronoiPartitionerTests {
    private let partitioner = VoronoiPartitioner()
    private let bounds = CGRect(x: -500, y: -500, width: 1000, height: 1000)

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Node.self, Edge.self, arachnode.Category.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeNode(_ context: ModelContext, name: String, categories: [arachnode.Category] = []) -> Node {
        let n = Node(name: name)
        context.insert(n)
        n.categories = categories
        return n
    }

    @Test("empty graph → empty partition")
    func emptyGraph() {
        let graph = GraphSnapshot(nodes: [], edges: [], categories: [])
        let result = partitioner.partition(graph: graph, bounds: bounds)
        #expect(result.isEmpty)
    }

    @Test("single uncategorized node → one cell covering nearly all of bounds")
    func singleUncategorized() throws {
        let context = try makeContext()
        let n = makeNode(context, name: "A")
        let graph = GraphSnapshot(nodes: [n], edges: [], categories: [])

        let result = partitioner.partition(graph: graph, bounds: bounds)
        #expect(result.count == 1)
        #expect(result[.uncategorized] != nil)
        // Only one seed → its cell is the entire bounds.
        let area = result[.uncategorized]!.area
        let boundsArea = bounds.width * bounds.height
        #expect(abs(area - boundsArea) < boundsArea * 0.001)
    }

    @Test("single categorized node → one cell covering bounds")
    func singleCategorized() throws {
        let context = try makeContext()
        let cat = arachnode.Category(name: "Cat"); context.insert(cat)
        let n = makeNode(context, name: "A", categories: [cat])
        let graph = GraphSnapshot(nodes: [n], edges: [], categories: [cat])

        let result = partitioner.partition(graph: graph, bounds: bounds)
        #expect(result.count == 1)
        #expect(result[.single(cat.id)] != nil)
        let area = result[.single(cat.id)]!.area
        let boundsArea = bounds.width * bounds.height
        #expect(abs(area - boundsArea) < boundsArea * 0.001)
    }

    @Test("two single-category nodes produce two non-overlapping cells covering bounds")
    func twoCategoriesPartitionBounds() throws {
        let context = try makeContext()
        let catA = arachnode.Category(name: "A"); context.insert(catA)
        let catB = arachnode.Category(name: "B"); context.insert(catB)
        let nA = makeNode(context, name: "nA", categories: [catA])
        let nB = makeNode(context, name: "nB", categories: [catB])
        let graph = GraphSnapshot(
            nodes: [nA, nB],
            edges: [],
            categories: [catA, catB]
        )

        let result = partitioner.partition(graph: graph, bounds: bounds)
        #expect(result.count == 2)
        let totalArea = result.values.reduce(0) { $0 + $1.area }
        let boundsArea = bounds.width * bounds.height
        #expect(abs(totalArea - boundsArea) < boundsArea * 0.01)
    }

    @Test("multi-category node gets its own combination cell")
    func multiCategoryGetsOwnCell() throws {
        let context = try makeContext()
        let catA = arachnode.Category(name: "A"); context.insert(catA)
        let catB = arachnode.Category(name: "B"); context.insert(catB)
        let nA = makeNode(context, name: "nA", categories: [catA])
        let nB = makeNode(context, name: "nB", categories: [catB])
        let nAB = makeNode(context, name: "nAB", categories: [catA, catB])
        let graph = GraphSnapshot(
            nodes: [nA, nB, nAB],
            edges: [],
            categories: [catA, catB]
        )

        let result = partitioner.partition(graph: graph, bounds: bounds)
        // Three keys: single A, single B, combination [A, B].
        #expect(result.count == 3)
        #expect(result[.single(catA.id)] != nil)
        #expect(result[.single(catB.id)] != nil)
        #expect(result[.combination([catA.id, catB.id])] != nil)
    }

    @Test("heavier-weighted seed gets a larger cell than a lighter one")
    func weightedCellsScaleWithNodeCount() throws {
        let context = try makeContext()
        let catA = arachnode.Category(name: "A"); context.insert(catA)
        let catB = arachnode.Category(name: "B"); context.insert(catB)

        // 20 nodes in catA, 1 in catB.
        var nodes: [Node] = []
        for _ in 0..<20 {
            nodes.append(makeNode(context, name: "a", categories: [catA]))
        }
        nodes.append(makeNode(context, name: "b", categories: [catB]))

        let graph = GraphSnapshot(
            nodes: nodes,
            edges: [],
            categories: [catA, catB]
        )

        let result = partitioner.partition(graph: graph, bounds: bounds)
        #expect(result.count == 2)
        let areaA = result[.single(catA.id)]?.area ?? 0
        let areaB = result[.single(catB.id)]?.area ?? 0
        #expect(
            areaA > areaB,
            "category A (20 nodes) should have a larger cell than B (1 node) — got A=\(areaA), B=\(areaB)"
        )
    }

    @Test("uncategorized + categorized both get cells; cells together cover bounds")
    func mixedCategorizedAndUncategorized() throws {
        let context = try makeContext()
        let cat = arachnode.Category(name: "Cat"); context.insert(cat)
        let categorized = makeNode(context, name: "c", categories: [cat])
        let uncategorized = makeNode(context, name: "u")
        let graph = GraphSnapshot(
            nodes: [categorized, uncategorized],
            edges: [],
            categories: [cat]
        )

        let result = partitioner.partition(graph: graph, bounds: bounds)
        #expect(result[.single(cat.id)] != nil)
        #expect(result[.uncategorized] != nil)
        let totalArea = result.values.reduce(0) { $0 + $1.area }
        let boundsArea = bounds.width * bounds.height
        #expect(abs(totalArea - boundsArea) < boundsArea * 0.01)
    }

    @Test("partitioning is deterministic — same graph produces same regions twice")
    func deterministic() throws {
        let context = try makeContext()
        let catA = arachnode.Category(name: "A"); context.insert(catA)
        let catB = arachnode.Category(name: "B"); context.insert(catB)
        let catC = arachnode.Category(name: "C"); context.insert(catC)
        let nA = makeNode(context, name: "nA", categories: [catA])
        let nB = makeNode(context, name: "nB", categories: [catB])
        let nC = makeNode(context, name: "nC", categories: [catC])
        let graph = GraphSnapshot(
            nodes: [nA, nB, nC],
            edges: [],
            categories: [catA, catB, catC]
        )

        let result1 = partitioner.partition(graph: graph, bounds: bounds)
        let result2 = partitioner.partition(graph: graph, bounds: bounds)
        // Compare semantic invariants — same key set, same per-cell area
        // and centroid — rather than strict polygon-array equality. The
        // half-plane-clipping order depends on dictionary iteration which
        // can produce equivalent polygons with vertices in different array
        // orders; that's a representation detail, not a determinism break.
        #expect(Set(result1.keys) == Set(result2.keys))
        for key in result1.keys {
            let r1 = result1[key]!
            let r2 = result2[key]!
            #expect(abs(r1.area - r2.area) < 1e-6)
            #expect(abs(r1.centroid.x - r2.centroid.x) < 1e-6)
            #expect(abs(r1.centroid.y - r2.centroid.y) < 1e-6)
        }
    }
}
