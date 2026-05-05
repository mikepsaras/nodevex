import Foundation
import CoreGraphics

/// Owns the live position state and runs the force simulation. Force-directed
/// is the only layout — alpha-decayed continuous physics, driven from
/// CanvasNSView's animation timer.
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

    private(set) var alpha: Double = 0
    private let alphaDecay: Double = 0.96
    private let alphaTarget: Double = 0.05
    private let alphaOnGraphChange: Double = 0.7

    private var draggedNodeID: UUID?
    private var draggedNodePosition: CGPoint?

    private let forceLayout = ForceDirectedLayout()
    private var lastGraph: GraphSnapshot?

    /// True once a graph has been applied — physics has something to simulate.
    /// CanvasNSView gates its animation timer on this. With `alphaTarget > 0`
    /// the sim never fully sleeps, so this stays true for the lifetime of the
    /// view; the gentle continuous drift is the source of the "fluid" feel.
    var isActive: Bool { lastGraph != nil }

    /// True while a drag is in progress. CanvasNSView gates its timer on this
    /// too so drag overrides apply each tick.
    var isDragging: Bool { draggedNodeID != nil }

    /// Reseed positions for new/removed nodes, reset alpha so the sim has
    /// energy to settle the change. Keeps existing positions for nodes that
    /// were already present. `seedOrigin` is the canvas-center-relative point
    /// new nodes should spawn around.
    func applyGraphChange(_ graph: GraphSnapshot, seedOrigin: CGPoint = .zero) {
        lastGraph = graph
        positions = forceLayout.seedPositions(
            graph: graph,
            previousPositions: positions,
            seedOrigin: seedOrigin
        )
        // Drop velocities for nodes no longer present; new nodes start
        // with zero velocity (the seed dictionary handles this implicitly).
        velocities = velocities.filter { positions[$0.key] != nil }
        alpha = alphaOnGraphChange
    }

    /// One physics step. While dragging, the rest of the graph is frozen —
    /// only the dragged node updates (override to cursor). This preserves the
    /// pre-drag equilibrium so on release the node has its full drag distance
    /// to traverse at the (low) floor velocity, producing a visible pull-back.
    @discardableResult
    func tick() -> Bool {
        if let nodeID = draggedNodeID, let pos = draggedNodePosition {
            positions[nodeID] = pos
            velocities[nodeID] = .zero
            return true
        }

        guard let graph = lastGraph else { return false }

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

    /// Wipes positions and velocities, re-seeds every node around
    /// `seedOrigin`, then runs the physics offline until convergence so the
    /// caller sees nodes already clustered around their categories rather
    /// than gradually drifting into place. Used by the Re-layout affordance.
    func reseedAll(seedOrigin: CGPoint = .zero) {
        guard let graph = lastGraph else { return }
        positions = forceLayout.seedPositions(
            graph: graph,
            previousPositions: [:],
            seedOrigin: seedOrigin
        )
        velocities = [:]

        // Pre-converge offline. With the visible alpha-decay on the live
        // simulation, the user would otherwise watch ~3-5 seconds of
        // category-cluster pull fighting repulsion. 200 iterations here
        // (~ms-scale even for a few hundred nodes) drains the settling
        // time into a single sub-frame so the new layout reads as a
        // deliberate snap, not a long drift.
        var preAlpha: Double = 1.0
        for _ in 0..<200 {
            let result = forceLayout.advance(
                graph: graph,
                positions: positions,
                velocities: velocities,
                alpha: preAlpha
            )
            positions = result.positions
            velocities = result.velocities
            preAlpha = alphaTarget + (preAlpha - alphaTarget) * alphaDecay
        }

        // Live simulation continues at the floor — gentle drift, no jolt.
        alpha = alphaTarget
    }
}
