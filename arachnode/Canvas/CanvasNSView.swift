import AppKit
import Foundation

/// Snapshot of the currently-revealed node + its phase. Drives the edge reveal
/// opacity used by the renderer. Top-level (rather than nested) so its enums
/// don't pick up `@MainActor` isolation from CanvasNSView, which makes their
/// auto-synthesized Equatable conformance unusable from non-isolated contexts.
struct RevealState {
    enum Source { case hover, modal }
    enum Phase {
        case fadingIn(startTime: Date, duration: TimeInterval)
        case visible
        case fadingOut(startTime: Date, duration: TimeInterval)
    }
    let nodeID: UUID
    let source: Source
    var phase: Phase
}

final class CanvasNSView: NSView {
    private let renderer: CanvasRenderer = CGCanvasRenderer()
    private let layoutEngine = LayoutEngine()
    private var graph = GraphSnapshot(nodes: [], edges: [], categories: [])
    private var positions: [UUID: CGPoint] = [:]
    /// Per-node display radius. Recomputed on every update() — driven by the
    /// current `NodeSizingMode` and each node's intrinsic value. Used by the
    /// renderer for circle/edge geometry and by hit-testing for click target.
    private var radii: [UUID: CGFloat] = [:]
    private var selectedNodeIDs: Set<UUID> = []
    private var lastGraphSignature: Int?

    private var edgeVisibility: EdgeVisibilityMode = .animated
    private var nodeSizing: NodeSizingMode = .fixed
    private var appearanceMode: AppearanceMode = .dim
    private var lastResetLayoutVersion: Int = 0
    private var animationPhase: CGFloat = 0
    private var animationTimer: Timer?

    var onSelectionChange: ((Set<UUID>) -> Void)?
    var onNodeFocus: ((UUID) -> Void)?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    /// Per ADR-0011: hovering a node reveals its connections after a delay,
    /// fades in/out, and the node itself gets an immediate highlight cue.
    private var highlightedNodeID: UUID?     // immediate — drives node fill / label shift
    private var hoverPendingNodeID: UUID?    // cursor is over this node, awaiting delay
    private var hoverDelayTimer: Timer?
    private let hoverDelay: TimeInterval = 0.6
    private let revealFadeInDuration: TimeInterval = 0.6
    private let revealFadeOutHoverDuration: TimeInterval = 0.2
    private let revealFadeOutModalDuration: TimeInterval = 1.0

    private var reveal: RevealState?
    private var trackingArea: NSTrackingArea?
    private var lastModalFocusedNodeID: UUID?

    /// Node hit on mouseDown. Consumed on mouseUp to decide whether to open
    /// the focus modal — cleared the moment a drag is detected so that a
    /// click-then-drag doesn't *also* fire the modal on release.
    private var pendingClickNodeID: UUID?

    /// Drag bookkeeping. The cursor's canvas-relative point at mouseDown,
    /// the dragged node's position at that moment, and a flag for whether
    /// motion has crossed the click→drag threshold.
    private struct DragState {
        let nodeID: UUID
        let downCanvasPoint: CGPoint
        let originalNodePosition: CGPoint
        var didCrossThreshold: Bool
    }
    private var dragState: DragState?
    private let dragThreshold: CGFloat = 3

    deinit {
        animationTimer?.invalidate()
        hoverDelayTimer?.invalidate()
    }

    func update(
        graph: GraphSnapshot,
        selectedNodeIDs: Set<UUID>,
        modalFocusedNodeID: UUID?,
        edgeVisibility: EdgeVisibilityMode,
        nodeSizing: NodeSizingMode,
        appearanceMode: AppearanceMode,
        resetLayoutVersion: Int
    ) {
        let signature = graphSignature(graph)
        if signature != lastGraphSignature {
            self.graph = graph
            layoutEngine.applyGraphChange(graph, seedOrigin: currentViewportCenterWorld())
            self.positions = layoutEngine.positions
            lastGraphSignature = signature
        } else {
            self.graph = graph
        }
        if resetLayoutVersion != lastResetLayoutVersion {
            layoutEngine.reseedAll(seedOrigin: currentViewportCenterWorld())
            positions = layoutEngine.positions
            lastResetLayoutVersion = resetLayoutVersion
        }
        if self.selectedNodeIDs != selectedNodeIDs {
            self.selectedNodeIDs = selectedNodeIDs
        }
        self.edgeVisibility = edgeVisibility
        self.nodeSizing = nodeSizing
        self.appearanceMode = appearanceMode
        // Recompute every update — value and sizing-mode changes don't shift
        // graphSignature, so the renderer needs a fresh map each time.
        self.radii = computeRadii(graph: graph, sizing: nodeSizing)

        if modalFocusedNodeID != lastModalFocusedNodeID {
            handleModalFocusChange(from: lastModalFocusedNodeID, to: modalFocusedNodeID)
            lastModalFocusedNodeID = modalFocusedNodeID
        }

        updateAnimationTimer()
        needsDisplay = true
    }

    private func handleModalFocusChange(from oldID: UUID?, to newID: UUID?) {
        if let newID {
            // Modal opened — reveal connections immediately, no fade-in for
            // a deliberate gesture. Cancel any in-flight hover delay.
            hoverDelayTimer?.invalidate()
            hoverDelayTimer = nil
            hoverPendingNodeID = nil
            reveal = RevealState(nodeID: newID, source: .modal, phase: .visible)
            return
        }

        guard let oldID else { return }

        // Modal closed. mouseMoved stops firing while the modal overlay is up,
        // so our cached hover state is stale — sample the current cursor
        // position. If the cursor is over a node, the reveal handoff is
        // instant (no fade-out, no fade-in delay) regardless of whether it's
        // the same node the modal was for. If the cursor is over empty
        // canvas, do the normal modal-tagged fade-out.
        if let cursorNodeID = currentCursorNodeID() {
            reveal = RevealState(nodeID: cursorNodeID, source: .hover, phase: .visible)
            highlightedNodeID = cursorNodeID
            hoverPendingNodeID = cursorNodeID
            hoverDelayTimer?.invalidate()
            hoverDelayTimer = nil
        } else {
            reveal = RevealState(
                nodeID: oldID,
                source: .modal,
                phase: .fadingOut(startTime: Date(), duration: revealFadeOutModalDuration)
            )
        }
    }

    /// Center of the visible scroll-view region in canvas-center-relative
    /// coords. Used as the seed origin for newly-created nodes so they spawn
    /// where the user is currently looking, not at the canvas origin.
    private func currentViewportCenterWorld() -> CGPoint {
        guard let scrollView = enclosingScrollView else { return .zero }
        let visible = scrollView.documentVisibleRect
        return CGPoint(
            x: visible.midX - bounds.midX,
            y: visible.midY - bounds.midY
        )
    }

    /// Look up which node (if any) the cursor is currently over by sampling
    /// `window.mouseLocationOutsideOfEventStream`. Useful when we need cursor
    /// position outside of a mouse event — e.g. on modal close, where
    /// mouseMoved didn't fire while the overlay was up.
    private func currentCursorNodeID() -> UUID? {
        guard let window = self.window else { return nil }
        let pointInView = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let canvasPoint = CGPoint(
            x: pointInView.x - bounds.midX,
            y: pointInView.y - bounds.midY
        )
        return findNodeID(at: canvasPoint)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let zoom = enclosingScrollView?.magnification ?? 1.0
        renderer.draw(
            in: context,
            bounds: bounds,
            graph: graph,
            positions: positions,
            radii: radii,
            selectedIDs: selectedNodeIDs,
            highlightedNodeID: highlightedNodeID,
            revealedNodeID: reveal?.nodeID,
            revealOpacity: currentRevealOpacity,
            edgeVisibility: edgeVisibility,
            animationPhase: animationPhase,
            zoom: zoom,
            appearanceMode: appearanceMode
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        // .inVisibleRect tracks the visible portion of the view as it grows /
        // scrolls — we don't have to re-create on resize.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    private func updateAnimationTimer() {
        // Timer drives three things: arrow flow on animated edges, hover-reveal
        // fade transitions, and the continuous force-physics tick (which also
        // applies the drag override). Run while any of them is active.
        if edgeVisibility == .animated || reveal != nil || layoutEngine.isActive || layoutEngine.isDragging {
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
            self.advanceRevealTransitions()
            // One physics step per frame. Pulls dragged nodes via overrides,
            // applies forces to the rest, decays alpha. When alpha settles
            // and other animation reasons go quiet, the timer self-stops.
            self.layoutEngine.tick()
            self.positions = self.layoutEngine.positions
            // If physics finished settling but other animations are still
            // active, we keep ticking; if everything's quiet, recompute the
            // timer state.
            if !self.layoutEngine.isActive && !self.layoutEngine.isDragging && self.edgeVisibility != .animated && self.reveal == nil {
                self.stopAnimationTimer()
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    private func advanceRevealTransitions() {
        guard let r = reveal else { return }
        switch r.phase {
        case .fadingIn(let startTime, let duration):
            if Date().timeIntervalSince(startTime) >= duration {
                reveal?.phase = .visible
            }
        case .visible:
            break
        case .fadingOut(let startTime, let duration):
            if Date().timeIntervalSince(startTime) >= duration {
                reveal = nil
                updateAnimationTimer()
            }
        }
    }

    /// Current reveal opacity (0...1). Renderer applies this to the alpha of
    /// edges connected to `revealedNodeID` when the global edge mode is hidden.
    private var currentRevealOpacity: CGFloat {
        guard let r = reveal else { return 0 }
        switch r.phase {
        case .fadingIn(let startTime, let duration):
            let elapsed = Date().timeIntervalSince(startTime)
            return CGFloat(min(elapsed / duration, 1.0))
        case .visible:
            return 1.0
        case .fadingOut(let startTime, let duration):
            let elapsed = Date().timeIntervalSince(startTime)
            return CGFloat(max(1.0 - elapsed / duration, 0))
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)

        let pointInView = convert(event.locationInWindow, from: nil)
        let canvasPoint = CGPoint(
            x: pointInView.x - bounds.midX,
            y: pointInView.y - bounds.midY
        )

        let hitID = findNodeID(at: canvasPoint)
        let modifiers = event.modifierFlags

        // Track click + drag intent in parallel. mouseUp picks the right one
        // based on whether motion crossed the drag threshold.
        pendingClickNodeID = hitID
        if let hitID, let originalPos = positions[hitID] {
            dragState = DragState(
                nodeID: hitID,
                downCanvasPoint: canvasPoint,
                originalNodePosition: originalPos,
                didCrossThreshold: false
            )
        } else {
            dragState = nil
        }

        // Plain click no longer selects — it opens the focus modal on mouseUp.
        // Selection requires shift (add) or command (toggle). Click on empty
        // canvas without a modifier still clears the selection.
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
        let cursorInView = convert(event.locationInWindow, from: nil)
        // Clamp the cursor to the visible viewport in canvas-local coords so
        // the dragged node sticks to the viewport edge if the cursor crosses it.
        let clampedView = clampToVisibleViewport(cursorInView)
        let canvasPoint = CGPoint(
            x: clampedView.x - bounds.midX,
            y: clampedView.y - bounds.midY
        )
        let dx = canvasPoint.x - state.downCanvasPoint.x
        let dy = canvasPoint.y - state.downCanvasPoint.y
        let nodePosition = CGPoint(
            x: state.originalNodePosition.x + dx,
            y: state.originalNodePosition.y + dy
        )

        if !state.didCrossThreshold && (dx * dx + dy * dy) > dragThreshold * dragThreshold {
            state.didCrossThreshold = true
            // Crossing the threshold means this is a drag, not a click.
            // Cancel the modal-open path and notify the engine so the dragged
            // node's position is overridden each tick while neighbors react
            // to it via the regular forces.
            pendingClickNodeID = nil
            layoutEngine.startDrag(nodeID: state.nodeID, position: nodePosition)
            // Suppress hover/highlight while dragging.
            updateHover(target: nil)
        } else if state.didCrossThreshold {
            layoutEngine.updateDrag(position: nodePosition)
        }

        dragState = state
        // Keep the timer awake so the drag override applies each tick.
        updateAnimationTimer()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragState = nil
            pendingClickNodeID = nil
        }

        if let state = dragState, state.didCrossThreshold {
            // Drag end — clear the engine's fix and let residual alpha pull
            // the node back toward force equilibrium.
            layoutEngine.endDrag()
            return
        }

        guard let nodeID = pendingClickNodeID else { return }
        let modifiers = event.modifierFlags
        if modifiers.isDisjoint(with: [.shift, .command, .option]) {
            onNodeFocus?(nodeID)
        }
    }

    /// Clamp a point in this view's coords to the enclosing scroll view's
    /// visible region. Used during drag so the dragged node sticks to the
    /// viewport edge when the cursor goes past it.
    private func clampToVisibleViewport(_ point: CGPoint) -> CGPoint {
        guard let scrollView = enclosingScrollView else { return point }
        let visibleRect = scrollView.contentView.bounds
        return CGPoint(
            x: min(max(point.x, visibleRect.minX), visibleRect.maxX),
            y: min(max(point.y, visibleRect.minY), visibleRect.maxY)
        )
    }

    override func mouseMoved(with event: NSEvent) {
        // Don't reveal during a drag — the user is busy with another gesture.
        // (mouseMoved typically doesn't fire during a drag, but be explicit.)
        if dragState?.didCrossThreshold == true {
            updateHover(target: nil)
            return
        }
        let pointInView = convert(event.locationInWindow, from: nil)
        let canvasPoint = CGPoint(
            x: pointInView.x - bounds.midX,
            y: pointInView.y - bounds.midY
        )
        updateHover(target: findNodeID(at: canvasPoint))
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(target: nil)
    }

    /// Drive the hover state machine from a (possibly-changed) cursor target.
    ///
    /// Two modes:
    /// 1. **Cold hover** (no reveal currently active) — the standard
    ///    600ms-delay-then-fade-in behavior.
    /// 2. **Active reveal** (a reveal is already showing or in fade-out) —
    ///    hovering instantly switches the reveal to the cursor's node with no
    ///    delay and no fade-in. Hovering off all nodes starts a quick (200ms)
    ///    hover-rate fade-out, even if the existing reveal was a slow
    ///    modal-tagged fade.
    ///
    /// Modal currently visible (open) is the one case that blocks hover — the
    /// canvas isn't really in focus then.
    private func updateHover(target nodeID: UUID?) {
        if let r = reveal, case .modal = r.source, case .visible = r.phase {
            return
        }

        if highlightedNodeID != nodeID {
            highlightedNodeID = nodeID
            needsDisplay = true
        }

        // Pointing-hand when the cursor is over a node OR while a drag is in
        // flight (so the grab cue persists through the gesture, even though
        // hover is suppressed during drag). Plain arrow otherwise.
        let overNode = nodeID != nil || dragState?.didCrossThreshold == true
        (overNode ? NSCursor.pointingHand : NSCursor.arrow).set()

        // A reveal is already active (any source, any phase except modal-visible
        // which we excluded above). The user's hover target wins immediately —
        // no delay, no fade-in — so an in-flight reveal can be redirected or
        // re-locked by simple cursor motion.
        if reveal != nil {
            if let nodeID {
                let needsRevealUpdate: Bool
                if let r = reveal, r.nodeID == nodeID,
                   case .visible = r.phase, case .hover = r.source {
                    needsRevealUpdate = false
                } else {
                    needsRevealUpdate = true
                }
                if needsRevealUpdate {
                    reveal = RevealState(nodeID: nodeID, source: .hover, phase: .visible)
                    needsDisplay = true
                    updateAnimationTimer()
                }
                hoverPendingNodeID = nodeID
                hoverDelayTimer?.invalidate()
                hoverDelayTimer = nil
            } else {
                // Cursor off all nodes — quick hover-rate fade-out, even if
                // the existing reveal was a slower modal-tagged fade.
                if let r = reveal {
                    switch r.phase {
                    case .fadingOut(_, let duration) where duration <= revealFadeOutHoverDuration:
                        break
                    default:
                        reveal?.phase = .fadingOut(startTime: Date(), duration: revealFadeOutHoverDuration)
                        updateAnimationTimer()
                    }
                }
                hoverPendingNodeID = nil
                hoverDelayTimer?.invalidate()
                hoverDelayTimer = nil
            }
            return
        }

        // Cold hover path: no reveal active, use the standard delay + fade-in.
        guard nodeID != hoverPendingNodeID else { return }
        hoverPendingNodeID = nodeID
        hoverDelayTimer?.invalidate()
        hoverDelayTimer = nil

        guard let nodeID else { return }
        let timer = Timer(timeInterval: hoverDelay, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard self.hoverPendingNodeID == nodeID else { return }
            self.reveal = RevealState(
                nodeID: nodeID,
                source: .hover,
                phase: .fadingIn(startTime: Date(), duration: self.revealFadeInDuration)
            )
            self.updateAnimationTimer()
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverDelayTimer = timer
    }

    private func findNodeID(at canvasPoint: CGPoint) -> UUID? {
        // Click target = max(actual radius, 12pt floor). The floor keeps tiny
        // value-scaled nodes hittable; large nodes use their actual radius
        // (no oversized invisible halo).
        let hitFloor: CGFloat = 12
        for node in graph.nodes.reversed() {
            guard let pos = positions[node.id] else { continue }
            let hitRadius = max(radii[node.id] ?? NodeSizingMode.defaultRadius, hitFloor)
            let dx = canvasPoint.x - pos.x
            let dy = canvasPoint.y - pos.y
            if dx * dx + dy * dy <= hitRadius * hitRadius {
                return node.id
            }
        }
        return nil
    }

    private func computeRadii(graph: GraphSnapshot, sizing: NodeSizingMode) -> [UUID: CGFloat] {
        var result: [UUID: CGFloat] = [:]
        result.reserveCapacity(graph.nodes.count)
        for node in graph.nodes {
            result[node.id] = sizing.radius(forValue: node.value)
        }
        return result
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

        var hasher = Hasher()
        hasher.combine(nodeIDs)
        hasher.combine(categoryMemberships)
        hasher.combine(edgeFingerprints)
        return hasher.finalize()
    }
}
