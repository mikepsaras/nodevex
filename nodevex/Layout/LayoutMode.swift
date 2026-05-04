import Foundation

/// User-selectable layout, plumbed from the canvas footer through CanvasView
/// down to CanvasNSView's LayoutEngine. Each case maps to a `LayoutStrategy`
/// implementation.
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

    var strategy: any LayoutStrategy {
        switch self {
        case .forceDirected: ForceDirectedLayout()
        case .hierarchical: HierarchicalLayout()
        }
    }
}
