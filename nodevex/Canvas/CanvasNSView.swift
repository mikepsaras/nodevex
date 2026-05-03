import AppKit
import Foundation

final class CanvasNSView: NSView {
    private let renderer: CanvasRenderer = CGCanvasRenderer()
    private let layoutEngine = LayoutEngine()
    private var graph = GraphSnapshot(nodes: [], edges: [], categories: [])
    private var positions: [UUID: CGPoint] = [:]
    private var selectedNodeIDs: Set<UUID> = []

    var onSelectionChange: ((Set<UUID>) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    @MainActor
    func update(graph: GraphSnapshot, selectedNodeIDs: Set<UUID>) {
        self.graph = graph
        layoutEngine.relayout(graph: graph)
        self.positions = layoutEngine.positions
        if self.selectedNodeIDs != selectedNodeIDs {
            self.selectedNodeIDs = selectedNodeIDs
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.draw(
            in: context,
            bounds: bounds,
            graph: graph,
            positions: positions,
            selectedIDs: selectedNodeIDs
        )
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let pointInView = convert(event.locationInWindow, from: nil)
        // Layout positions are centered around (0, 0); the renderer offsets by
        // canvas midpoint to draw. Mirror that to test in canvas-space.
        let canvasPoint = CGPoint(
            x: pointInView.x - bounds.midX,
            y: pointInView.y - bounds.midY
        )
        let hitID = findNodeID(at: canvasPoint)
        let modifiers = event.modifierFlags

        var newSelection = selectedNodeIDs
        if let hitID {
            if modifiers.contains(.shift) {
                newSelection.insert(hitID)
            } else if modifiers.contains(.command) {
                if newSelection.contains(hitID) {
                    newSelection.remove(hitID)
                } else {
                    newSelection.insert(hitID)
                }
            } else {
                newSelection = [hitID]
            }
        } else if modifiers.isDisjoint(with: [.shift, .command]) {
            newSelection = []
        }

        guard newSelection != selectedNodeIDs else { return }
        selectedNodeIDs = newSelection
        needsDisplay = true
        onSelectionChange?(newSelection)
    }

    private func findNodeID(at canvasPoint: CGPoint) -> UUID? {
        // Pill bounds match CGCanvasRenderer's nodeWidth (120) and nodeHeight (32).
        // TODO: extract pill metrics to a shared constant when we add shape variants.
        let halfWidth: CGFloat = 60
        let halfHeight: CGFloat = 16
        // Reverse iteration so the most-recently-added (top-most-drawn) node hits first.
        for node in graph.nodes.reversed() {
            guard let pos = positions[node.id] else { continue }
            if abs(canvasPoint.x - pos.x) <= halfWidth,
               abs(canvasPoint.y - pos.y) <= halfHeight {
                return node.id
            }
        }
        return nil
    }
}
