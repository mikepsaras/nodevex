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

    /// Simulation energy. 1.0 = high motion, decays toward `alphaTarget`
    /// (not zero) so the sim never fully freezes — connected nodes keep
    /// drifting gently rather than locking into rigid positions.
    private(set) var alpha: Double = 0
    private let alphaDecay: Double = 0.96
    /// Floor that alpha asymptotes to. Keeps the simulation alive at very
    /// low energy so the graph reads as fluid rather than static.
    private let alphaTarget: Double = 0.05
    /// Initial alpha for graph-change perturbations. Slightly below the
    /// drag-release reset so adding a node / assigning a category settles
    /// gradually — but high enough that integrated cluster pull over the
    /// settle period actually moves things into formation.
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

    /// Reseed positions for new/removed nodes, reset alpha so the sim has
    /// energy to settle the change. Keeps existing positions for nodes that
    /// were already present.
    func applyGraphChange(_ graph: GraphSnapshot) {
        lastGraph = graph
        switch currentMode {
        case .forceDirected:
            positions = forceLayout.seedPositions(
                graph: graph,
                previousPositions: positions
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

    /// One physics step. Always returns true while in force-directed mode —
    /// the simulation runs continuously, with alpha decaying toward
    /// `alphaTarget` rather than zero.
    @discardableResult
    func tick() -> Bool {
        guard let graph = lastGraph, isActive else { return false }
        let result = forceLayout.advance(
            graph: graph,
            positions: positions,
            velocities: velocities,
            alpha: alpha,
            draggedNodeID: draggedNodeID,
            draggedNodePosition: draggedNodePosition
        )
        positions = result.positions
        velocities = result.velocities
        // Asymptote toward alphaTarget instead of zero — so alpha never
        // crosses below the floor, simulation stays alive at low energy.
        alpha = alphaTarget + (alpha - alphaTarget) * alphaDecay
        return true
    }

    func startDrag(nodeID: UUID, position: CGPoint) {
        draggedNodeID = nodeID
        draggedNodePosition = position
        // Wake the simulation so neighbors react to the perturbation in real
        // time. While the drag is held, the dragged node's position is
        // overwritten each tick.
        alpha = 1.0
    }

    func updateDrag(position: CGPoint) {
        draggedNodePosition = position
        // Keep the sim energetic so neighbors track the moving cursor.
        alpha = max(alpha, 0.5)
    }

    func endDrag() {
        draggedNodeID = nil
        draggedNodePosition = nil
        // Inject energy so the residual sim pulls the node back toward
        // equilibrium, matching the Obsidian-graph drag-back feel.
        alpha = max(alpha, 0.7)
    }

    private func applyModeSwitch() {
        guard let lastGraph else { return }
        applyGraphChange(lastGraph)
    }
}
