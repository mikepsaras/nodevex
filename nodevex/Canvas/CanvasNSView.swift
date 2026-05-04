import AppKit
import Foundation

final class CanvasNSView: NSView {
    private let renderer: CanvasRenderer = CGCanvasRenderer()
    private let layoutEngine = LayoutEngine()
    private var graph = GraphSnapshot(nodes: [], edges: [], categories: [])
    private var positions: [UUID: CGPoint] = [:]
    private var selectedNodeIDs: Set<UUID> = []
    private var lastGraphSignature: Int?

    private var edgeVisibility: EdgeVisibilityMode = .animated
    private var animationPhase: CGFloat = 0
    private var animationTimer: Timer?

    var onSelectionChange: ((Set<UUID>) -> Void)?
    var onNodeFocus: ((UUID) -> Void)?
    var onNodePin: ((UUID, CGPoint) -> Void)?
    var onNodeUnpin: ((UUID) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private struct DragState {
        let nodeID: UUID
        let downPoint: CGPoint
        let originalPosition: CGPoint
        var didCrossThreshold: Bool
    }
    private var dragState: DragState?
    private let dragThreshold: CGFloat = 3

    deinit {
        animationTimer?.invalidate()
    }

    @MainActor
    func update(graph: GraphSnapshot, selectedNodeIDs: Set<UUID>, edgeVisibility: EdgeVisibilityMode) {
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
        self.edgeVisibility = edgeVisibility
        // Always re-evaluate the timer's running state. Comparing-then-acting
        // misses the initial mount when both values are .animated and never
        // started the timer in the first place.
        updateAnimationTimer()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        renderer.draw(
            in: context,
            bounds: bounds,
            graph: graph,
            positions: positions,
            selectedIDs: selectedNodeIDs,
            edgeVisibility: edgeVisibility,
            animationPhase: animationPhase
        )
    }

    private func updateAnimationTimer() {
        if edgeVisibility == .animated {
            startAnimationTimer()
        } else {
            stopAnimationTimer()
        }
    }

    private func startAnimationTimer() {
        guard animationTimer == nil else { return }
        // .common run-loop mode keeps animation ticking while the user is
        // panning / scrolling / interacting with menus.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            // Phase grows cumulatively — never wraps. Each arrow does its own
            // modulo at draw time. Wrapping the shared phase causes arrows
            // with non-1.0 speed to snap back together at the wrap point,
            // which reads as a visible jump.
            self.animationPhase += 0.005
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let pointInView = convert(event.locationInWindow, from: nil)
        let canvasPoint = CGPoint(
            x: pointInView.x - bounds.midX,
            y: pointInView.y - bounds.midY
        )

        if event.clickCount == 2, let hitID = findNodeID(at: canvasPoint) {
            onNodeFocus?(hitID)
            return
        }

        let hitID = findNodeID(at: canvasPoint)
        let modifiers = event.modifierFlags

        // Option-click on a pinned node unpins it and leaves selection alone.
        if modifiers.contains(.option),
           let hitID,
           let node = graph.nodes.first(where: { $0.id == hitID }),
           node.isPinned {
            onNodeUnpin?(hitID)
            return
        }

        // Set up potential drag-to-pin. Selection still happens immediately
        // below — drag and selection layer cleanly because they don't conflict.
        if let hitID, let pos = positions[hitID] {
            dragState = DragState(
                nodeID: hitID,
                downPoint: canvasPoint,
                originalPosition: pos,
                didCrossThreshold: false
            )
        } else {
            dragState = nil
        }

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

    override func mouseDragged(with event: NSEvent) {
        guard var state = dragState else { return }
        let pointInView = convert(event.locationInWindow, from: nil)
        let canvasPoint = CGPoint(
            x: pointInView.x - bounds.midX,
            y: pointInView.y - bounds.midY
        )

        let dx = canvasPoint.x - state.downPoint.x
        let dy = canvasPoint.y - state.downPoint.y
        if !state.didCrossThreshold && (dx * dx + dy * dy) > dragThreshold * dragThreshold {
            state.didCrossThreshold = true
        }

        if state.didCrossThreshold {
            positions[state.nodeID] = CGPoint(
                x: state.originalPosition.x + dx,
                y: state.originalPosition.y + dy
            )
            needsDisplay = true
        }

        dragState = state
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragState = nil }
        guard let state = dragState, state.didCrossThreshold else { return }
        if let pos = positions[state.nodeID] {
            onNodePin?(state.nodeID, pos)
        }
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
        // Build sets so the hash is independent of the array order @Query
        // returns. Without this, a SwiftUI re-render that re-fetches edges
        // in a different order would change the signature, fire a relayout,
        // and shift node positions — that's the "node drifts when toggling
        // edge visibility" blip.
        let nodeIDs: Set<UUID> = Set(graph.nodes.map { $0.id })
        let categoryMemberships: Set<String> = Set(graph.nodes.flatMap { node in
            node.categories.map { "\(node.id):\($0.id)" }
        })
        let edgeFingerprints: Set<String> = Set(graph.edges.map { edge in
            "\(edge.id):\(edge.sourceID):\(edge.targetID)"
        })
        // Pin *bool* — not coords. We want unpin to trigger a relayout (so the
        // node reflows), but dragging an already-pinned node should not (we
        // update positions directly during drag and don't want a force-iteration
        // pass to fight that).
        let pinnedIDs: Set<UUID> = Set(graph.nodes.filter { $0.isPinned }.map { $0.id })

        var hasher = Hasher()
        hasher.combine(nodeIDs)
        hasher.combine(categoryMemberships)
        hasher.combine(edgeFingerprints)
        hasher.combine(pinnedIDs)
        return hasher.finalize()
    }
}
