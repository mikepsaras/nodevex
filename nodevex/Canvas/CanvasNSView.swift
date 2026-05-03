import AppKit
import Foundation

final class CanvasNSView: NSView {
    private let renderer: CanvasRenderer = CGCanvasRenderer()
    private let layoutEngine = LayoutEngine()
    private var graph = GraphSnapshot(nodes: [], edges: [], categories: [])
    private var positions: [UUID: CGPoint] = [:]
    private var selectedNodeIDs: Set<UUID> = []
    private var lastGraphSignature: Int?

    var onSelectionChange: ((Set<UUID>) -> Void)?
    var onNodeFocus: ((UUID) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    @MainActor
    func update(graph: GraphSnapshot, selectedNodeIDs: Set<UUID>) {
        let signature = graphSignature(graph)
        if signature != lastGraphSignature {
            self.graph = graph
            layoutEngine.relayout(graph: graph)
            self.positions = layoutEngine.positions
            lastGraphSignature = signature
        } else {
            self.graph = graph
        }
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
        let canvasPoint = CGPoint(
            x: pointInView.x - bounds.midX,
            y: pointInView.y - bounds.midY
        )

        // Double-click on a node opens the focus modal. Selection from the prior
        // single-click is fine to leave in place; the modal sits on top of it.
        if event.clickCount == 2, let hitID = findNodeID(at: canvasPoint) {
            onNodeFocus?(hitID)
            return
        }

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
        let hitRadius: CGFloat = 16
        let hitRadiusSquared = hitRadius * hitRadius
        for node in graph.nodes.reversed() {
            guard let pos = positions[node.id] else { continue }
            let dx = canvasPoint.x - pos.x
            let dy = canvasPoint.y - pos.y
            if dx * dx + dy * dy <= hitRadiusSquared {
                return node.id
            }
        }
        return nil
    }

    private func graphSignature(_ graph: GraphSnapshot) -> Int {
        var hasher = Hasher()
        for node in graph.nodes {
            hasher.combine(node.id)
        }
        for edge in graph.edges {
            hasher.combine(edge.id)
            hasher.combine(edge.sourceID)
            hasher.combine(edge.targetID)
        }
        return hasher.finalize()
    }
}
