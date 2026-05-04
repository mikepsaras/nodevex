import Foundation

/// User-selectable layout. Force-directed runs continuously (tick-based,
/// alpha-decayed). Hierarchical is a one-shot batch. `LayoutEngine` selects
/// behavior off this enum directly — no shared protocol bridge.
enum LayoutMode: String, CaseIterable, Identifiable {
    case forceDirected
    case hierarchical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .forceDirected: "Force-directed"
        case .hierarchical: "Hierarchical"
        }
    }
}
