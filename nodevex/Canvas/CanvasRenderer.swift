import CoreGraphics
import Foundation

protocol CanvasRenderer {
    func draw(
        in context: CGContext,
        bounds: CGRect,
        graph: GraphSnapshot,
        positions: [UUID: CGPoint],
        selectedIDs: Set<UUID>,
        edgeVisibility: EdgeVisibilityMode,
        animationPhase: CGFloat
    )
}
