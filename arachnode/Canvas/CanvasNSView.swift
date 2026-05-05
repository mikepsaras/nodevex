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
    /// Mutable, in-progress layout. Holds per-cell ripple states that
    /// advance one tick per animation frame; positions and radii surface
    /// through it. The previous layout is replaced (not retained) on each
    /// `runLayout` — but the new one is seeded with the previous frame's
    /// positions so existing nodes ripple from where they were instead of
    /// snapping to the packer's reset.
    private var liveLayout: LiveLayoutState = .empty
    private var positions: [UUID: CGPoint] = [:]
    /// Per-node display radius. Sourced from `liveLayout.radii` on each
    /// layout run. Used by the renderer for circle/edge geometry and by
    /// hit-testing for click target.
    private var radii: [UUID: CGFloat] = [:]
    /// True while any cell's ripple is still active. Drives the animation
    /// timer alongside edge animation and hover-reveal.
    private var rippleActive: Bool = false
    private var selectedNodeIDs: Set<UUID> = []
    private var lastGraphSignature: Int?

    private var edgeVisibility: EdgeVisibilityMode = .animated
    private var nodeSizing: NodeSizingMode = .fixed
    private var appearanceMode: AppearanceMode = .dim
    private var showCategoryRegions: Bool = false
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
    /// for plain clicks (no modifiers). Cleared the moment a drag is
    /// engaged so the click→focus path doesn't fire on drag-release.
    private var pendingClickNodeID: UUID?

    /// Drag bookkeeping. The cursor's canvas point at mouseDown, the
    /// dragged node's CategoryKey + radius captured then, and a flag for
    /// whether motion has crossed the click→drag threshold. The dragged
    /// node's position is pinned in its cell's ripple state during the
    /// drag (via `fixedIndex`); neighbors continue rippling around it.
    private struct DragState {
        let nodeID: UUID
        let cellKey: CategoryKey
        let nodeRadius: CGFloat
        let downCanvasPoint: CGPoint
        let originalNodePosition: CGPoint
        var didCrossThreshold: Bool
    }
    private var dragState: DragState?
    private let dragThreshold: CGFloat = 3

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
        appearanceMode: AppearanceMode,
        showCategoryRegions: Bool
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
        self.showCategoryRegions = showCategoryRegions

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
    /// bounds. Builds a fresh `LiveLayoutState` (partition + pack +
    /// initial ripple states) seeded with the previous frame's positions,
    /// so existing nodes ripple from where they were rather than snapping
    /// to the packer's reset. The animation timer drives the ripple from
    /// here on; positions update each frame via `tickLayout`.
    private func runLayout() {
        liveLayout = layoutController.prepareLayout(
            graph: graph,
            sizing: nodeSizing,
            bounds: layoutBounds(),
            initialPositions: positions
        )
        positions = liveLayout.positions
        radii = liveLayout.radii
        rippleActive = !liveLayout.rippleStates.isEmpty
    }

    /// Advance the layout's ripple by one frame. Called from the animation
    /// timer. Returns `true` while any cell is still active; once `false`,
    /// the timer can stop ticking the ripple (other animations may still
    /// keep the timer alive).
    @discardableResult
    private func tickLayout() -> Bool {
        let active = layoutController.tick(&liveLayout)
        positions = liveLayout.positions
        rippleActive = active
        return active
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
            regions: liveLayout.regions,
            radii: radii,
            selectedIDs: selectedNodeIDs,
            highlightedNodeID: highlightedNodeID,
            revealedNodeID: reveal?.nodeID,
            revealOpacity: currentRevealOpacity,
            edgeVisibility: edgeVisibility,
            animationPhase: animationPhase,
            zoom: zoom,
            appearanceMode: appearanceMode,
            showRegions: showCategoryRegions
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
        // reveal fade transitions, and the per-cell ripple animation
        // (advances positions one tick per frame until each cell settles).
        if edgeVisibility == .animated || reveal != nil || rippleActive {
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
            // Layout ripple — each tick advances every cell's per-node
            // physics by one step, with positions updating in place.
            if self.rippleActive {
                self.tickLayout()
            }
            if self.edgeVisibility != .animated
                && self.reveal == nil
                && !self.rippleActive {
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

        pendingClickNodeID = hitID
        // Capture drag state if we hit a node — actual drag engagement
        // requires crossing the threshold in mouseDragged. The CategoryKey
        // tells us which cell's ripple state to update during the drag.
        if let hitID,
           let pos = positions[hitID],
           let radius = radii[hitID],
           let node = graph.nodes.first(where: { $0.id == hitID }) {
            let cellKey = CategoryKey.from(categoryIDs: node.categories.map { $0.id })
            dragState = DragState(
                nodeID: hitID,
                cellKey: cellKey,
                nodeRadius: radius,
                downCanvasPoint: canvasPoint,
                originalNodePosition: pos,
                didCrossThreshold: false
            )
        } else {
            dragState = nil
        }

        // Plain click opens the focus modal (consumed in mouseUp).
        // Selection requires shift (add) or command (toggle). Click on
        // empty canvas without a modifier clears the selection.
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

        let pointInView = convert(event.locationInWindow, from: nil)
        let canvasPoint = CGPoint(
            x: pointInView.x - bounds.midX,
            y: pointInView.y - bounds.midY
        )
        let dx = canvasPoint.x - state.downCanvasPoint.x
        let dy = canvasPoint.y - state.downCanvasPoint.y

        // Engagement: only commit to drag once the cursor has moved past
        // the threshold. Below threshold we treat it as a still-pending
        // click so a slightly-jittery click doesn't accidentally drag.
        if !state.didCrossThreshold,
           (dx * dx + dy * dy) > dragThreshold * dragThreshold {
            state.didCrossThreshold = true
            // Drag commits — abandon the click→focus path and suppress
            // hover during the gesture.
            pendingClickNodeID = nil
            updateHover(target: nil)
        }

        if state.didCrossThreshold {
            let target = CGPoint(
                x: state.originalNodePosition.x + dx,
                y: state.originalNodePosition.y + dy
            )
            // Clamp to the cell's polygon, inset by the node's radius so
            // the entire circle stays inside its cell. Voronoi cells are
            // convex, so a single iterative clamp converges quickly.
            if let region = liveLayout.regions[state.cellKey] {
                let clamped = region.clampedToInset(target, by: state.nodeRadius)
                // Update the ripple state for this cell: pin the dragged
                // node at the clamped position so neighbors repel from it
                // each tick. We also bump alpha if it had decayed to zero
                // so the ripple resumes ticking around the dragged node.
                if var cellState = liveLayout.rippleStates[state.cellKey],
                   let nodeIndex = cellState.ids.firstIndex(of: state.nodeID) {
                    cellState.positions[nodeIndex] = clamped
                    cellState.velocities[nodeIndex] = .zero
                    cellState.fixedIndex = nodeIndex
                    if cellState.alpha < 0.5 { cellState.alpha = 0.5 }
                    liveLayout.rippleStates[state.cellKey] = cellState
                }
                positions[state.nodeID] = clamped
                rippleActive = true
                updateAnimationTimer()
                needsDisplay = true
            }
        }

        dragState = state
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragState = nil
            pendingClickNodeID = nil
        }

        // Drag end — release the pin and bump alpha so neighbors continue
        // rippling for a moment after release (settling around the dropped
        // node's new spot). Skip the click→focus path entirely.
        if let state = dragState, state.didCrossThreshold {
            if var cellState = liveLayout.rippleStates[state.cellKey] {
                cellState.fixedIndex = nil
                if cellState.alpha < 0.5 { cellState.alpha = 0.5 }
                liveLayout.rippleStates[state.cellKey] = cellState
                rippleActive = true
                updateAnimationTimer()
            }
            return
        }

        // Plain click — fire focus modal.
        guard let nodeID = pendingClickNodeID else { return }
        let modifiers = event.modifierFlags
        if modifiers.isDisjoint(with: [.shift, .command, .option]) {
            onNodeFocus?(nodeID)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // Suppress hover entirely while a drag gesture is engaged.
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
        // (no oversized invisible halo). `positions` is the most-current
        // per-frame snapshot (updated by the ripple tick), so hit-tests
        // land on the rendered circle even mid-animation.
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
