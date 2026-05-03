import AppKit

final class CanvasNSView: NSView {
    private let renderer: CanvasRenderer = CGCanvasRenderer()

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.draw(in: context, bounds: bounds)
    }
}
