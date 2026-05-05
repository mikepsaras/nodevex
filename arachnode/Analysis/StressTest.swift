import SwiftData

/// Throwaway debug seeder. Bound to ⇧⌘T from `DocumentView`. Drops 500
/// nodes across 8 categories into the model context so the canvas can be
/// sanity-checked under load. Additive — runs on top of whatever is already
/// there, so the user can keep firing it to escalate (1k, 1.5k, …).
enum StressTest {
    static func seed500Nodes(in context: ModelContext) {
        var categories: [Category] = []
        for i in 1...8 {
            categories.append(
                CategoryCommands.createCategory(name: "Stress \(i)", in: context)
            )
        }

        var stressNodes: [Node] = []
        stressNodes.reserveCapacity(500)
        for i in 1...500 {
            let node = NodeCommands.createNode(name: "Stress \(i)", in: context)
            if let cat = categories.randomElement() {
                CategoryCommands.toggleAssignment(node: node, category: cat)
            }
            stressNodes.append(node)
        }

        // Edges are pure decoration in the deterministic-layout era — they
        // don't influence positions. A modest sprinkling exercises the
        // hover-reveal path and edge animation without producing wall-of-
        // spaghetti at 500 nodes. Duplicates / self-edges are rejected by
        // EdgeCommands.
        for _ in 0..<60 {
            guard let source = stressNodes.randomElement(),
                  let target = stressNodes.randomElement(),
                  source.id != target.id else { continue }
            EdgeCommands.createEdge(from: source.id, to: target.id, in: context)
        }
    }
}
