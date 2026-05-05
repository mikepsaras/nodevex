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
    /// Most recent layout snapshot — settled positions, radii, and the
    /// per-cell region polygons. Positions update on graph change (via
    /// `runLayout`) and on drag (via `mouseDragged`'s direct edits).
    private var lastLayoutResult = LayoutResult.empty
    private var positions: [UUID: CGPoint] = [:]
    /// Per-node display radius. Sourced from `lastLayoutResult.radii` on
    /// each layout run. Used by the renderer for circle/edge geometry
    /// and by hit-testing for click target.
    private var radii: [UUID: CGFloat] = [:]
    private var selectedNodeIDs: Set<UUID> = []
    private var lastGraphSignature: Int?

    /// Smooth-tween state for graph-change transitions. When `runLayout`
    /// produces new positions, the previous frame's positions are saved
    /// here and `transitionStart` is set; the renderer then interpolates
    /// (smoothstep eased) between previous and current positions for
    /// `transitionDuration` seconds. Drag edits don't tween — they
    /// update `positions` directly so the cursor stays in sync.
    private var previousPositions: [UUID: CGPoint] = [:]
    private var transitionStart: Date?
    private let transitionDuration: TimeInterval = 0.25

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
    /// node's position is updated directly each `mouseDragged` event;
    /// any same-cell neighbor it overlaps gets bumped out of the way
    /// (see `resolveBumps`). `sameCellNodeIDs` is captured at mouseDown
    /// so the bump pass doesn't re-filter the graph each event.
    private struct DragState {
        let nodeID: UUID
        let cellKey: CategoryKey
        let nodeRadius: CGFloat
        let downCanvasPoint: CGPoint
        let originalNodePosition: CGPoint
        var didCrossThreshold: Bool
        let sameCellNodeIDs: [UUID]
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
        // Now that the view has a screen, size the document to match the
        // screen's visibleFrame so the canvas hugs the layout (no empty
        // padding for zoom-out to reveal). Then recompute layout against
        // those same bounds.
        syncCanvasSize()
        if !graph.nodes.isEmpty {
            runLayout()
            needsDisplay = true
        }
    }

    /// Fired when the window moves to a different screen, or when display
    /// hardware/configuration changes. Resize the canvas to match the new
    /// screen, then recompute layout against the new bounds.
    @objc private func displayMayHaveChanged() {
        syncCanvasSize()
        guard !graph.nodes.isEmpty else { return }
        runLayout()
        needsDisplay = true
    }

    /// Pass the current `layoutBounds().size` down to the enclosing
    /// `CanvasScrollView` as the document size. Idempotent — the scroll
    /// view skips no-op assignments.
    private func syncCanvasSize() {
        guard let scrollView = enclosingScrollView as? CanvasScrollView else { return }
        scrollView.setCanvasSize(layoutBounds().size)
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
    /// bounds. Seeds the controller with the previous frame's positions
    /// so existing nodes start where they were (smooth handover) when
    /// possible. After the run, snaps the new layout in place but starts
    /// a smooth tween from the previous positions to the new ones over
    /// `transitionDuration` seconds — that's the only animation between
    /// successive layouts.
    private func runLayout() {
        let positionsBefore = positions
        let result = layoutController.computeLayout(
            graph: graph,
            sizing: nodeSizing,
            bounds: layoutBounds(),
            initialPositions: positions
        )
        lastLayoutResult = result
        radii = result.radii
        positions = result.positions
        if !positionsBefore.isEmpty {
            previousPositions = positionsBefore
            transitionStart = Date()
        } else {
            previousPositions = [:]
            transitionStart = nil
        }
    }

    /// 0…1 progress through the active transition (1 when no transition).
    private var transitionProgress: CGFloat {
        guard let start = transitionStart else { return 1 }
        let elapsed = Date().timeIntervalSince(start)
        return CGFloat(min(elapsed / transitionDuration, 1.0))
    }

    /// Position lookup used by the renderer and hit-testing. Interpolates
    /// from `previousPositions` to `positions` while a transition is
    /// active; once the transition completes, returns `positions` as-is.
    /// Nodes added in the new layout (no previous position) appear at
    /// their final position immediately.
    private var effectivePositions: [UUID: CGPoint] {
        let t = transitionProgress
        guard t < 1.0, !previousPositions.isEmpty else { return positions }
        let smoothT = t * t * (3 - 2 * t)  // smoothstep ease-in-out
        var result: [UUID: CGPoint] = [:]
        result.reserveCapacity(positions.count)
        for (id, current) in positions {
            if let prev = previousPositions[id] {
                result[id] = CGPoint(
                    x: prev.x + (current.x - prev.x) * smoothT,
                    y: prev.y + (current.y - prev.y) * smoothT
                )
            } else {
                result[id] = current
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
            regions: lastLayoutResult.regions,
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
        // reveal fade transitions, and the layout transition tween
        // (interpolating positions from previous to current after a
        // graph change).
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
            // frames return current positions directly.
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

        pendingClickNodeID = hitID
        // Capture drag state if we hit a node — actual drag engagement
        // requires crossing the threshold in mouseDragged. The CategoryKey
        // tells us which cell to clamp drag motion to; `sameCellNodeIDs`
        // pre-computes the same-cell neighbor list so bump-resolution
        // doesn't refilter the graph each mouseDragged event.
        if let hitID,
           let pos = effectivePositions[hitID],
           let radius = radii[hitID],
           let node = graph.nodes.first(where: { $0.id == hitID }) {
            let cellKey = CategoryKey.from(categoryIDs: node.categories.map { $0.id })
            let sameCellNodeIDs = graph.nodes.compactMap { other -> UUID? in
                guard other.id != hitID else { return nil }
                let key = CategoryKey.from(categoryIDs: other.categories.map { $0.id })
                return key == cellKey ? other.id : nil
            }
            dragState = DragState(
                nodeID: hitID,
                cellKey: cellKey,
                nodeRadius: radius,
                downCanvasPoint: canvasPoint,
                originalNodePosition: pos,
                didCrossThreshold: false,
                sameCellNodeIDs: sameCellNodeIDs
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
            // Drag commits — abandon the click→focus path, suppress
            // hover, and abort any in-progress smooth-tween (drag is
            // direct manipulation; the tween would compete).
            pendingClickNodeID = nil
            updateHover(target: nil)
            transitionStart = nil
            previousPositions = [:]
        }

        if state.didCrossThreshold {
            let target = CGPoint(
                x: state.originalNodePosition.x + dx,
                y: state.originalNodePosition.y + dy
            )
            // Clamp to the cell's polygon, inset by the node's radius so
            // the entire circle stays inside the cell.
            if let region = lastLayoutResult.regions[state.cellKey] {
                let clamped = region.clampedToInset(target, by: state.nodeRadius)
                positions[state.nodeID] = clamped
                // Bump-resolve same-cell neighbors out of the way if the
                // dragged node now overlaps them. Single pass — chain
                // reactions are unusual at typical cell sizes and node
                // counts.
                resolveBumps(
                    draggedID: state.nodeID,
                    draggedPos: clamped,
                    draggedRadius: state.nodeRadius,
                    sameCellNodeIDs: state.sameCellNodeIDs,
                    in: region
                )
                needsDisplay = true
            }
        }

        dragState = state
    }

    /// Push same-cell neighbors that overlap the dragged node out of the
    /// way. Each overlapping neighbor is moved to the closest non-overlap
    /// point along the line from the dragged node, then clamped to the
    /// cell so it doesn't escape. Non-overlapping neighbors stay put —
    /// drag affects nothing it doesn't actually touch.
    private func resolveBumps(
        draggedID: UUID,
        draggedPos: CGPoint,
        draggedRadius: CGFloat,
        sameCellNodeIDs: [UUID],
        in region: Region
    ) {
        for neighborID in sameCellNodeIDs {
            guard let neighborPos = positions[neighborID],
                  let neighborRadius = radii[neighborID] else { continue }
            let dx = neighborPos.x - draggedPos.x
            let dy = neighborPos.y - draggedPos.y
            let dist = sqrt(dx * dx + dy * dy)
            let minDist = draggedRadius + neighborRadius
            guard dist < minDist else { continue }
            // Compute push direction. If the two are essentially
            // coincident, push in an arbitrary direction so we still
            // separate them.
            let dirX: CGFloat
            let dirY: CGFloat
            if dist > 0.001 {
                dirX = dx / dist
                dirY = dy / dist
            } else {
                dirX = 1
                dirY = 0
            }
            let bumped = CGPoint(
                x: draggedPos.x + dirX * minDist,
                y: draggedPos.y + dirY * minDist
            )
            positions[neighborID] = region.clampedToInset(bumped, by: neighborRadius)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            dragState = nil
            pendingClickNodeID = nil
        }

        // Drag-end is a no-op for the layout — positions stay where the
        // user dropped them. Just skip the click→focus path so the modal
        // doesn't fire after a drag.
        if dragState?.didCrossThreshold == true { return }

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
        // (no oversized invisible halo). Hit-test reads `effectivePositions`
        // so clicks during a smooth-tween land on the rendered (interpolated)
        // circle, not the post-tween target.
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
