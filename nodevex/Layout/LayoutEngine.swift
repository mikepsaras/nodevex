import Foundation
import CoreGraphics

/// Owns the live position state and runs whichever layout the user has
/// selected. Force-directed runs as a continuous tick-based simulation —
/// alpha-decayed, driven from CanvasNSView's animation timer. Hierarchical
/// runs once as a batch when the graph changes or the mode is selected.
///
/// Drag is a perturbation, not a commit. While dragging, the dragged node's
/// position is overridden to the cursor (so it pulls neighbors via the same
/// forces). On release, the override clears and residual alpha carries
/// everything back toward equilibrium — no separate animation phase.
///
/// Always called from the main thread (CanvasNSView's timer + SwiftUI update
/// path), but no `@MainActor` so it composes cleanly with NSView's timer
/// callbacks under Swift 6 strict isolation.
final class LayoutEngine {
    private(set) var positions: [UUID: CGPoint] = [:]
    private var velocities: [UUID: CGPoint] = [:]
    var currentMode: LayoutMode = .forceDirected {
        didSet {
            guard currentMode != oldValue else { return }
            applyModeSwitch()
        }
    }

    private(set) var alpha: Double = 0
    private let alphaDecay: Double = 0.96
    private let alphaTarget: Double = 0.05
    private let alphaOnGraphChange: Double = 0.7

    private var draggedNodeID: UUID?
    private var draggedNodePosition: CGPoint?

    private let forceLayout = ForceDirectedLayout()
    private let hierarchicalLayout = HierarchicalLayout()
    private var lastGraph: GraphSnapshot?

    /// True while in force-directed mode. With `alphaTarget > 0` the sim
    /// never fully sleeps — the gentle continuous drift is the source of the
    /// "fluid" feel. CanvasNSView gates its animation timer on this.
    var isActive: Bool { currentMode == .forceDirected }

    /// True while a drag is in progress. CanvasNSView gates its timer on
    /// this too so drag works in hierarchical mode (where `isActive` is
    /// false and physics is otherwise dormant).
    var isDragging: Bool { draggedNodeID != nil }

    /// Reseed positions for new/removed nodes, reset alpha so the sim has
    /// energy to settle the change. Keeps existing positions for nodes that
    /// were already present. `seedOrigin` is the canvas-center-relative point
    /// new nodes should spawn around (in force-directed mode); hierarchical
    /// ignores it.
    func applyGraphChange(_ graph: GraphSnapshot, seedOrigin: CGPoint = .zero) {
        lastGraph = graph
        switch currentMode {
        case .forceDirected:
            positions = forceLayout.seedPositions(
                graph: graph,
                previousPositions: positions,
                seedOrigin: seedOrigin
            )
            // Drop velocities for nodes no longer present; new nodes start
            // with zero velocity (the seed dictionary handles this implicitly).
            velocities = velocities.filter { positions[$0.key] != nil }
            alpha = alphaOnGraphChange
        case .hierarchical:
            positions = hierarchicalLayout.compute(
                graph: graph,
                previousPositions: positions
            )
            velocities.removeAll()  // hierarchical is stateless; clear physics state
            alpha = 0
        }
    }

    /// One physics step. While dragging, the rest of the graph is frozen —
    /// only the dragged node updates (override to cursor). This preserves the
    /// pre-drag equilibrium so on release the node has its full drag distance
    /// to traverse at the (low) floor velocity, producing a visible pull-back.
    /// Drag override runs regardless of mode so dragging still works in
    /// hierarchical (where physics is otherwise off).
    @discardableResult
    func tick() -> Bool {
        if let nodeID = draggedNodeID, let pos = draggedNodePosition {
            positions[nodeID] = pos
            velocities[nodeID] = .zero
            return true
        }

        guard let graph = lastGraph, isActive else { return false }

        let result = forceLayout.advance(
            graph: graph,
            positions: positions,
            velocities: velocities,
            alpha: alpha
        )
        positions = result.positions
        velocities = result.velocities
        alpha = alphaTarget + (alpha - alphaTarget) * alphaDecay
        return true
    }

    func startDrag(nodeID: UUID, position: CGPoint) {
        draggedNodeID = nodeID
        draggedNodePosition = position
    }

    func updateDrag(position: CGPoint) {
        draggedNodePosition = position
    }

    func endDrag() {
        draggedNodeID = nil
        draggedNodePosition = nil
        // Drop alpha to the floor so pull-back is at the gentle drift velocity
        // regardless of how energetic the sim was before/during the drag.
        alpha = alphaTarget
    }

    private func applyModeSwitch() {
        guard let lastGraph else { return }
        applyGraphChange(lastGraph)
    }
}
