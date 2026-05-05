import SwiftUI
import SwiftData
import AppKit

struct CanvasView: NSViewRepresentable {
    @Binding var selectedNodeIDs: Set<UUID>
    var edgeVisibility: EdgeVisibilityMode
    var modalFocusedNodeID: UUID?
    var onNodeFocus: (UUID) -> Void
    var appearanceMode: AppearanceMode
    @Query(sort: \Node.createdAt, order: .forward) private var nodes: [Node]
    @Query private var edges: [Edge]
    @Query private var categories: [Category]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CanvasScrollView {
        let scrollView = CanvasScrollView()
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 4.0
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SemanticColors.AppKit.canvasBackground(for: appearanceMode)

        let canvas = CanvasNSView()
        canvas.onSelectionChange = { [weak coordinator = context.coordinator] newSelection in
            coordinator?.parent.selectedNodeIDs = newSelection
        }
        canvas.onNodeFocus = { [weak coordinator = context.coordinator] nodeID in
            coordinator?.parent.onNodeFocus(nodeID)
        }
        scrollView.documentView = canvas

        return scrollView
    }

    func updateNSView(_ nsView: CanvasScrollView, context: Context) {
        context.coordinator.parent = self
        guard let canvas = nsView.documentView as? CanvasNSView else { return }
        nsView.backgroundColor = SemanticColors.AppKit.canvasBackground(for: appearanceMode)
        // Sort edges by id so render order is stable across @Query refetches —
        // otherwise overlapping edges flicker when SwiftData re-orders.
        let sortedEdges = edges.sorted(by: { $0.id.uuidString < $1.id.uuidString })
        let snapshot = GraphSnapshot(nodes: nodes, edges: sortedEdges, categories: categories)
        canvas.update(
            graph: snapshot,
            selectedNodeIDs: selectedNodeIDs,
            modalFocusedNodeID: modalFocusedNodeID,
            edgeVisibility: edgeVisibility,
            appearanceMode: appearanceMode
        )
    }

    final class Coordinator {
        var parent: CanvasView
        init(parent: CanvasView) {
            self.parent = parent
        }
    }
}

final class CanvasScrollView: NSScrollView {
    /// Fixed 100k × 100k document area — effectively infinite at any
    /// reasonable zoom level. Node positions are canvas-center-relative, so
    /// the geometric midpoint is the world origin.
    private let canvasSize = NSSize(width: 100_000, height: 100_000)
    private var isAdjusting = false
    private var hasAppliedInitialZoom = false

    override func tile() {
        super.tile()
        guard !isAdjusting else { return }
        isAdjusting = true
        defer { isAdjusting = false }
        applyCanvasAndMagnification()
    }

    private func applyCanvasAndMagnification() {
        guard let documentView else { return }
        if documentView.frame.size != canvasSize {
            documentView.frame.size = canvasSize
            documentView.needsDisplay = true
        }
        if !hasAppliedInitialZoom {
            magnification = 1.0
            // Center the viewport on the canvas's geometric midpoint. Node
            // positions are stored relative to canvas center, so without this
            // the user sees the canvas's empty top-left corner on launch
            // while every actual node sits behind the scroll boundary.
            let viewportSize = contentView.frame.size
            let scrollX = canvasSize.width / 2 - viewportSize.width / 2
            let scrollY = canvasSize.height / 2 - viewportSize.height / 2
            contentView.scroll(to: NSPoint(x: max(0, scrollX), y: max(0, scrollY)))
            reflectScrolledClipView(contentView)
            hasAppliedInitialZoom = true
        }
    }
}
