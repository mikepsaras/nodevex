import AppKit
import Foundation

final class CanvasNSView: NSView {
    private let renderer: CanvasRenderer = CGCanvasRenderer()
    private let layoutEngine = LayoutEngine()
    private var graph = GraphSnapshot(nodes: [], edges: [], categories: [])
    private var positions: [UUID: CGPoint] = [:]

    override var isFlipped: Bool { true }

    @MainActor
    func update(graph: GraphSnapshot) {
        self.graph = graph
        layoutEngine.relayout(graph: graph)
        self.positions = layoutEngine.positions
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.draw(in: context, bounds: bounds, graph: graph, positions: positions)
    }
}
