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
    private let layoutController = LayoutController()
    private var graph = GraphSnapshot(nodes: [], edges: [], categories: [])
    private var lastLayoutResult = LayoutResult.empty
    private var positions: [UUID: CGPoint] = [:]
    /// Per-node display radius. Recomputed on every layout — driven by the
    /// current `NodeSizingMode` and each node's intrinsic value. Used by the
    /// renderer for circle/edge geometry and by hit-testing for click target.
    private var radii: [UUID: CGFloat] = [:]
    private var selectedNodeIDs: Set<UUID> = []
    private var lastGraphSignature: Int?

    /// Snapshot of node positions before the most recent layout run.
    /// Combined with `transitionStart` and `transitionDuration` to
    /// interpolate from old positions to new on graph change, so the
    /// re-layout reads as a smooth slide rather than an abrupt teleport.
    private var previousPositions: [UUID: CGPoint] = [:]
    private var transitionStart: Date?
    private let transitionDuration: TimeInterval = 0.25

    private var edgeVisibility: EdgeVisibilityMode = .animated
    private var nodeSizing: NodeSizingMode = .fixed
    private var appearanceMode: AppearanceMode = .dim
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

    /// Node hit on mouseDown. Consumed on mouseUp to fire `onNodeFocus`
    /// for plain clicks (no modifiers).
    private var pendingClickNodeID: UUID?

    deinit {
        NotificationCenter.default.removeObserver(self)
        animationTimer?.invalidate()
        hoverDelayTimer?.invalidate()
    }

    func update(
        graph: GraphSnapshot,
        selectedNodeIDs: Set<UUID>,
        modalFocusedNodeID: UUID?,
        edgeVisibility: EdgeVisibilityMode,
        nodeSizing: NodeSizingMode,
        appearanceMode: AppearanceMode
    ) {
        let signature = graphSignature(graph)
        let sizingChanged = self.nodeSizing != nodeSizing
        let needsRelayout = signature != lastGraphSignature || sizingChanged
        if needsRelayout {
            self.graph = graph
            self.nodeSizing = nodeSizing
            runLayout()
            lastGraphSignature = signature
        } else {
            self.graph = graph
        }
        if self.selectedNodeIDs != selectedNodeIDs {
            self.selectedNodeIDs = selectedNodeIDs
        }
        self.edgeVisibility = edgeVisibility
        self.appearanceMode = appearanceMode

        if modalFocusedNodeID != lastModalFocusedNodeID {
            handleModalFocusChange(from: lastModalFocusedNodeID, to: modalFocusedNodeID)
            lastModalFocusedNodeID = modalFocusedNodeID
        }

        updateAnimationTimer()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Re-register screen-change observers for the new window. Removing
        // any prior observers first keeps things clean if the view is moved
        // between windows.
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayMayHaveChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(displayMayHaveChanged),
                name: NSWindow.didChangeScreenNotification,
                object: window
            )
        }
        // Now that the view has a screen, recompute layout for the cached
        // graph against the screen's actual visible frame.
        if !graph.nodes.isEmpty {
            runLayout()
            needsDisplay = true
        }
    }

    /// Fired when the window moves to a different screen, or when display
    /// hardware/configuration changes. Recompute layout against the new
    /// bounds so the partition fills the active display.
    @objc private func displayMayHaveChanged() {
        guard !graph.nodes.isEmpty else { return }
        runLayout()
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

    /// Layout extent — the active screen's visible frame, centered at the
    /// world origin. Display-pegged: the layout fills the screen at its
    /// native dimensions regardless of the current window size, and only
    /// re-runs when the screen itself changes (different display or
    /// display-config event), not on window resize.
    private func layoutBounds() -> CGRect {
        let size = window?.screen?.visibleFrame.size
            ?? CGSize(width: 1500, height: 1500)
        return CGRect(
            x: -size.width / 2,
            y: -size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Re-run the layout pipeline against the current graph, sizing, and
    /// bounds, refreshing cached positions and radii. The renderer reads
    /// from these caches via `effectivePositions`, which interpolates
    /// between `previousPositions` and `positions` while a transition is
    /// active.
    private func runLayout() {
        let positionsBefore = positions
        let result = layoutController.computeLayout(
            graph: graph,
            sizing: nodeSizing,
            bounds: layoutBounds()
        )
        lastLayoutResult = result
        positions = result.positions
        radii = computeRadii(graph: graph, sizing: nodeSizing)
        // Trigger a transition only if there was a prior layout to slide
        // from. First-time layout (empty positionsBefore) snaps into place
        // without animation.
        if !positionsBefore.isEmpty {
            previousPositions = positionsBefore
            transitionStart = Date()
        } else {
            previousPositions = [:]
            transitionStart = nil
        }
    }

    /// 0...1 progress through the active transition, or 1 when idle.
    private var transitionProgress: CGFloat {
        guard let start = transitionStart else { return 1 }
        let elapsed = Date().timeIntervalSince(start)
        return CGFloat(min(elapsed / transitionDuration, 1.0))
    }

    /// Position lookup used by both the renderer and hit-testing. During a
    /// transition, interpolates each node from its previous position toward
    /// its current position with smoothstep easing. Nodes that didn't exist
    /// in the previous layout (newly added) appear at their final position
    /// without animation. Nodes that were removed are silently dropped.
    private var effectivePositions: [UUID: CGPoint] {
        let t = transitionProgress
        guard t < 1.0, !previousPositions.isEmpty else { return positions }
        // Smoothstep ease-in-out: 3t² − 2t³.
        let smoothT = t * t * (3 - 2 * t)
        var result: [UUID: CGPoint] = [:]
        result.reserveCapacity(positions.count)
        for (id, current) in positions {
            if let prev = previousPositions[id] {
                result[id] = CGPoint(
                    x: prev.x + (current.x - prev.x) * smoothT,
                    y: prev.y + (current.y - prev.y) * smoothT
                )
            } else {
                result[id] = current  // New node — appear at final position.
            }
        }
        return result
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
            positions: effectivePositions,
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
        // Timer drives three things: arrow flow on animated edges, hover-
        // reveal fade transitions, and the layout transition (interpolating
        // positions on graph change). The deterministic layout itself
        // doesn't tick — physics is gone.
        let transitionActive = transitionStart != nil && transitionProgress < 1.0
        if edgeVisibility == .animated || reveal != nil || transitionActive {
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
            // Layout transition completion — once we've crossed the
            // duration, drop the previous-positions snapshot so subsequent
            // frames return current positions directly without interpolation.
            if self.transitionStart != nil, self.transitionProgress >= 1.0 {
                self.transitionStart = nil
                self.previousPositions = [:]
            }
            let transitionActive = self.transitionStart != nil
            if self.edgeVisibility != .animated
                && self.reveal == nil
                && !transitionActive {
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

        // Plain click on a node opens the focus modal (consumed in mouseUp).
        // Selection requires shift (add) or command (toggle). Click on empty
        // canvas without a modifier clears the selection. Drag is no longer
        // a gesture — the deterministic layout doesn't accept manual
        // perturbation, so there's no DragState bookkeeping to maintain.
        pendingClickNodeID = hitID

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

    override func mouseUp(with event: NSEvent) {
        defer { pendingClickNodeID = nil }
        guard let nodeID = pendingClickNodeID else { return }
        let modifiers = event.modifierFlags
        if modifiers.isDisjoint(with: [.shift, .command, .option]) {
            onNodeFocus?(nodeID)
        }
    }

    override func mouseMoved(with event: NSEvent) {
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

        // Pointing-hand when the cursor is over a node, plain arrow otherwise.
        (nodeID != nil ? NSCursor.pointingHand : NSCursor.arrow).set()

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
        // (no oversized invisible halo). Hit-test uses interpolated positions
        // during transitions so clicks land on the rendered circle, not the
        // post-transition target.
        let positionsForHit = effectivePositions
        let hitFloor: CGFloat = 12
        for node in graph.nodes.reversed() {
            guard let pos = positionsForHit[node.id] else { continue }
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
        // returns — a SwiftUI re-render that re-fetches edges in a different
        // order would otherwise change the signature and trigger an
        // unnecessary relayout. Node fingerprints include `value`, so when
        // a user adjusts a node's value-slider in the modal (which can
        // change its display radius under `.scaledByValue`), the signature
        // moves and the layout re-runs.
        let nodeFingerprints: Set<String> = Set(graph.nodes.map { "\($0.id):\($0.value)" })
        let categoryMemberships: Set<String> = Set(graph.nodes.flatMap { node in
            node.categories.map { "\(node.id):\($0.id)" }
        })
        let edgeFingerprints: Set<String> = Set(graph.edges.map { edge in
            "\(edge.id):\(edge.sourceID):\(edge.targetID)"
        })

        var hasher = Hasher()
        hasher.combine(nodeFingerprints)
        hasher.combine(categoryMemberships)
        hasher.combine(edgeFingerprints)
        return hasher.finalize()
    }
}
