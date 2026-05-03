import AppKit
import CoreGraphics

struct CGCanvasRenderer: CanvasRenderer {
    func draw(in context: CGContext, bounds: CGRect) {
        context.setFillColor(SemanticColors.AppKit.canvasBackground.cgColor)
        context.fill(bounds)
    }
}
