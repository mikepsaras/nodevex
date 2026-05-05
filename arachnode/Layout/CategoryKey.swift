import Foundation

/// Identity for one cell in the layout partition. Every node maps to exactly
/// one `CategoryKey`, derived from its category memberships:
///
/// - `.uncategorized` — the node has no categories. All such nodes share one
///   peripheral cell.
/// - `.single(id)` — the node belongs to exactly one category.
/// - `.combination(ids)` — the node belongs to two or more categories. Each
///   distinct multi-category combination gets its own cell, positioned at
///   the centroid of the constituent single-category seeds. This is what
///   places shared nodes on the visual boundary between groups instead of
///   forcing them into one category arbitrarily.
enum CategoryKey: Hashable {
    case uncategorized
    case single(UUID)
    case combination(Set<UUID>)

    /// The set of category IDs this key represents. Empty for `.uncategorized`.
    var categoryIDs: Set<UUID> {
        switch self {
        case .uncategorized: []
        case .single(let id): [id]
        case .combination(let ids): ids
        }
    }

    /// Canonical key for a node's category list. Single-element lists become
    /// `.single`, two-or-more become `.combination`, empty becomes
    /// `.uncategorized`. The combination case stores a `Set`, so `[a, b]` and
    /// `[b, a]` produce equal keys.
    static func from(categoryIDs ids: [UUID]) -> CategoryKey {
        switch ids.count {
        case 0: .uncategorized
        case 1: .single(ids[0])
        default: .combination(Set(ids))
        }
    }
}
