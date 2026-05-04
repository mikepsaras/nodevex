import Foundation
import SwiftUI

struct ResolvedNodeStyle {
    var fillColor: Color
    var borderColor: Color
    var borderWidth: Double
    var shape: NodeShape
}

struct ResolvedEdgeStyle {
    var color: Color
    var lineWidth: Double
    var dashPattern: [Double]
    var headShape: ArrowHeadShape
    var animationSpeed: Double
}

struct DocumentTheme: Codable, Hashable {}

struct AppDefaults {
    static let `default` = AppDefaults()
}

struct StyleResolver {
    let documentTheme: DocumentTheme?
    let appDefaults: AppDefaults

    init(documentTheme: DocumentTheme? = nil, appDefaults: AppDefaults = .default) {
        self.documentTheme = documentTheme
        self.appDefaults = appDefaults
    }

    func style(for node: Node) -> ResolvedNodeStyle {
        ResolvedNodeStyle(
            fillColor: SemanticColors.nodeFill,
            borderColor: SemanticColors.nodeBorder,
            borderWidth: 0.5,
            shape: .circle
        )
    }

    func style(for edge: Edge) -> ResolvedEdgeStyle {
        let color: Color = switch edge.valence {
        case .positive: SemanticColors.edgePositive
        case .negative: SemanticColors.edgeNegative
        case .neutral: SemanticColors.edgeDefault
        }
        return ResolvedEdgeStyle(
            color: color,
            lineWidth: 1.5,
            dashPattern: [],
            headShape: .triangle,
            animationSpeed: edge.strength
        )
    }
}
