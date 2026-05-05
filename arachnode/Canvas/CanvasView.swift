import SwiftUI
import SwiftData
import AppKit

struct CanvasView: NSViewRepresentable {
    @Binding var selectedNodeIDs: Set<UUID>
    var edgeVisibility: EdgeVisibilityMode
    var nodeSizing: NodeSizingMode
    var modalFocusedNodeID: UUID?
    var onNodeFocus: (UUID) -> Void
    var appearanceMode: AppearanceMode
    @Environment(\.showCategoryRegions) private var showCategoryRegions
    @Query(sort: \Node.createdAt, order: .forward) private var nodes: [Node]
    @Query private var edges: [Edge]
    @Query private var categories: [Category]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CanvasScrollView {
        let scrollView = CanvasScrollView()
        scrollView.allowsMagnification = true
        // minMagnification is recomputed dynamically by `CanvasScrollView`
        // whenever the document or viewport size changes — see the
        // `applyCanvasAndMagnification` logic. Keep an initial floor of
        // 0.5× as a safe default before the first tile pass.
        scrollView.minMagnification = 0.5
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
            nodeSizing: nodeSizing,
            appearanceMode: appearanceMode,
            showCategoryRegions: showCategoryRegions
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
    /// Document size in canvas-local coordinates. Defaults to a sensible
    /// pre-attach value before the canvas determines the active screen's
    /// visibleFrame. After the first `setCanvasSize(_:)`, the document
    /// frame is sized to match the layout extent — so zooming-out can
    /// never reveal empty canvas around the layout (the document IS the
    /// layout area).
    private var canvasSize = NSSize(width: 1500, height: 1000)
    private var isAdjusting = false
    private var hasAppliedInitialZoom = false

    /// Update the document size in response to layout-bounds changes
    /// (typically a display change, since `CanvasNSView.layoutBounds()`
    /// reads the active screen's visibleFrame). Triggers a re-tile so
    /// `minMagnification` is recomputed against the new size.
    func setCanvasSize(_ size: NSSize) {
        guard size.width > 0, size.height > 0 else { return }
        guard size != canvasSize else { return }
        canvasSize = size
        needsLayout = true
    }

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

        // Compute the minimum magnification dynamically: at minimum zoom
        // the document fills the viewport (or the viewport fills the
        // document, when the window is bigger than the layout). Either
        // way there's never empty canvas around the document at max
        // zoom-out.
        let viewportSize = contentView.frame.size
        if viewportSize.width > 0, viewportSize.height > 0,
           canvasSize.width > 0, canvasSize.height > 0 {
            let fitWidth = viewportSize.width / canvasSize.width
            let fitHeight = viewportSize.height / canvasSize.height
            let computedMin = min(fitWidth, fitHeight)
            // Floor at 0.1× to avoid pathological tiny values; allow >1×
            // when the viewport exceeds the document (zoom IS the
            // minimum in that case — the layout fills the viewport).
            minMagnification = max(0.1, computedMin)
            if magnification < minMagnification {
                magnification = minMagnification
            }
        }

        if !hasAppliedInitialZoom {
            magnification = max(1.0, minMagnification)
            // Center viewport on the document midpoint. Node positions
            // are stored relative to the document's geometric center, so
            // without this the user sees an empty corner on launch.
            let scrollX = canvasSize.width / 2 - viewportSize.width / 2
            let scrollY = canvasSize.height / 2 - viewportSize.height / 2
            contentView.scroll(to: NSPoint(x: max(0, scrollX), y: max(0, scrollY)))
            reflectScrolledClipView(contentView)
            hasAppliedInitialZoom = true
        }
    }
}
