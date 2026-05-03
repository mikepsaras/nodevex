import Foundation

enum EdgeVisibilityMode: String, CaseIterable, Identifiable {
    case hidden
    case staticVisible
    case animated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hidden: "Edges hidden"
        case .staticVisible: "Edges static"
        case .animated: "Edges animated"
        }
    }

    var iconName: String {
        switch self {
        case .hidden: "eye.slash"
        case .staticVisible: "minus"
        case .animated: "dot.radiowaves.right"
        }
    }
}
