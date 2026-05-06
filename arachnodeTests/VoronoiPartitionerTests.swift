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

    @Test("default config: 1 uncategorized cell at center + 6 phantom outer slots")
    func defaultSevenCellConfiguration() throws {
        let context = try makeContext()
        let n = makeNode(context, name: "A")
        let graph = GraphSnapshot(nodes: [n], edges: [], categories: [])

        let result = partitioner.partition(graph: graph, bounds: bounds)
        // 1 uncategorized + 6 empty inner-ring slots = 7 cells.
        #expect(result.count == 7)
        #expect(result[.uncategorized] != nil)
        for slot in 0..<6 {
            #expect(result[.empty(slotIndex: slot)] != nil, "missing phantom slot \(slot)")
        }
        // Together they tessellate the bounds.
        let totalArea = result.values.reduce(0) { $0 + $1.area }
        let boundsArea = bounds.width * bounds.height
        #expect(abs(totalArea - boundsArea) < boundsArea * 0.001)
    }

    @Test("uncategorized cell sits at the canvas center")
    func uncategorizedAtCenter() throws {
        let context = try makeContext()
        let n = makeNode(context, name: "A")
        let graph = GraphSnapshot(nodes: [n], edges: [], categories: [])

        let result = partitioner.partition(graph: graph, bounds: bounds)
        let canvasCenter = CGPoint(x: bounds.midX, y: bounds.midY)
        let centroid = result[.uncategorized]!.centroid
        // With 6 surrounding equal-weight phantoms, the uncategorized
        // cell is a regular hexagon centered on the seed.
        #expect(abs(centroid.x - canvasCenter.x) < 5)
        #expect(abs(centroid.y - canvasCenter.y) < 5)
    }

    @Test("single category → 1 single + 5 phantom + uncategorized = 7 cells")
    func singleCategoryFillsOneOfSixOuterSlots() throws {
        let context = try makeContext()
        let cat = arachnode.Category(name: "Cat"); context.insert(cat)
        let n = makeNode(context, name: "A", categories: [cat])
        let graph = GraphSnapshot(nodes: [n], edges: [], categories: [cat])

        let result = partitioner.partition(graph: graph, bounds: bounds)
        #expect(result.count == 7)
        #expect(result[.single(cat.id)] != nil)
        #expect(result[.uncategorized] != nil)
        // 5 of the 6 inner-ring slots are still phantom (the category
        // takes slot 0).
        var phantomCount = 0
        for slot in 0..<6 {
            if result[.empty(slotIndex: slot)] != nil { phantomCount += 1 }
        }
        #expect(phantomCount == 5)
    }

    @Test("two categories → 2 single + 4 phantom + uncategorized = 7 cells")
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
        #expect(result.count == 7)
        #expect(result[.single(catA.id)] != nil)
        #expect(result[.single(catB.id)] != nil)
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
        // 2 singles + 1 combination + 4 phantom + 1 uncategorized = 8.
        #expect(result.count == 8)
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

    @Test("six categories fill the inner ring, no phantoms remain")
    func sixCategoriesFillInnerRing() throws {
        let context = try makeContext()
        var cats: [arachnode.Category] = []
        for i in 0..<6 {
            let c = arachnode.Category(name: "C\(i)"); context.insert(c)
            cats.append(c)
        }
        // One node anchors keyCounts so partition() doesn't short-circuit;
        // the slot-assignment logic ranges over `graph.categories`, not
        // node membership, so a single node in any category is enough.
        let n = makeNode(context, name: "n", categories: [cats[0]])
        let graph = GraphSnapshot(nodes: [n], edges: [], categories: cats)

        let result = partitioner.partition(graph: graph, bounds: bounds)
        // 6 singles + 0 phantoms + 1 uncategorized = 7.
        #expect(result.count == 7)
        for cat in cats {
            #expect(result[.single(cat.id)] != nil)
        }
        for slot in 0..<6 {
            #expect(result[.empty(slotIndex: slot)] == nil)
        }
    }

    @Test("seven categories: inner ring full, 7th goes to outer ring")
    func seventhCategoryGoesToOuterRing() throws {
        let context = try makeContext()
        var cats: [arachnode.Category] = []
        for i in 0..<7 {
            let c = arachnode.Category(name: "C\(i)"); context.insert(c)
            cats.append(c)
        }
        let n = makeNode(context, name: "n", categories: [cats[0]])
        let graph = GraphSnapshot(nodes: [n], edges: [], categories: cats)

        let result = partitioner.partition(graph: graph, bounds: bounds)
        // 7 singles + 0 phantoms + 1 uncategorized = 8.
        #expect(result.count == 8)
        for cat in cats {
            #expect(result[.single(cat.id)] != nil)
        }
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
