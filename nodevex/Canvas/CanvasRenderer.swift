import CoreGraphics

protocol CanvasRenderer {
    func draw(in context: CGContext, bounds: CGRect)
}
