import CoreGraphics
import Foundation

protocol CanvasRenderer {
    func draw(
        in context: CGContext,
        bounds: CGRect,
        graph: GraphSnapshot,
        positions: [UUID: CGPoint],
        selectedIDs: Set<UUID>,
        highlightedNodeID: UUID?,
        revealedNodeID: UUID?,
        revealOpacity: CGFloat,
        edgeVisibility: EdgeVisibilityMode,
        animationPhase: CGFloat,
        zoom: CGFloat,
        appearanceMode: AppearanceMode
    )
}
