import Foundation

/// Identity for one cell in the layout partition. Most cells are derived
/// directly from a node's category memberships:
///
/// - `.uncategorized` — the node has no categories. The default 7-cell
///   layout puts uncategorized nodes in the central cell — that's where
///   new nodes spawn before they're assigned to a category.
/// - `.single(id)` — the node belongs to exactly one category.
/// - `.combination(ids)` — the node belongs to two or more categories. Each
///   distinct multi-category combination gets its own cell, positioned at
///   the centroid of the constituent single-category seeds. This is what
///   places shared nodes on the visual boundary between groups instead of
///   forcing them into one category arbitrarily.
///
/// Plus one type emitted only by the partitioner for visual placeholders:
///
/// - `.empty(slotIndex:)` — a phantom slot in the inner ring with no
///   associated category yet. Nodes never carry this key (`from(...)`
///   never returns it); the partitioner emits it so that the canvas
///   always shows the "6 around 1" cell configuration even when fewer
///   than 6 categories exist. As the user adds categories, slots fill
///   in and the phantom keys disappear.
enum CategoryKey: Hashable {
    case uncategorized
    case single(UUID)
    case combination(Set<UUID>)
    case empty(slotIndex: Int)

    /// The set of category IDs this key represents. Empty for both
    /// `.uncategorized` (nodes without a category) and `.empty`
    /// (placeholder slots with no associated category yet).
    var categoryIDs: Set<UUID> {
        switch self {
        case .uncategorized: []
        case .single(let id): [id]
        case .combination(let ids): ids
        case .empty: []
        }
    }

    /// Canonical key for a node's category list. Single-element lists become
    /// `.single`, two-or-more become `.combination`, empty becomes
    /// `.uncategorized`. The combination case stores a `Set`, so `[a, b]` and
    /// `[b, a]` produce equal keys. Never returns `.empty` — that's a
    /// partitioner-only key for placeholder slots.
    static func from(categoryIDs ids: [UUID]) -> CategoryKey {
        switch ids.count {
        case 0: .uncategorized
        case 1: .single(ids[0])
        default: .combination(Set(ids))
        }
    }
}
