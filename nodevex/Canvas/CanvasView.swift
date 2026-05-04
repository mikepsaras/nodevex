import SwiftUI
import SwiftData
import AppKit

struct CanvasView: NSViewRepresentable {
    @Binding var selectedNodeIDs: Set<UUID>
    var edgeVisibility: EdgeVisibilityMode
    var layoutMode: LayoutMode
    var modalFocusedNodeID: UUID?
    var onNodeFocus: (UUID) -> Void
    // Sort by createdAt forward so the canvas processes nodes in creation
    // order. Hierarchical layout's barycenter sort treats isolated nodes'
    // position in the input array as their tie-break score, so a stable input
    // order is what makes layouts predictable.
    @Query(sort: \Node.createdAt, order: .forward) private var nodes: [Node]
    @Query private var edges: [Edge]
    @Query private var categories: [Category]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CanvasScrollView {
        let scrollView = CanvasScrollView()
        scrollView.allowsMagnification = true
        // Asymmetric zoom range. Capped zoom-in keeps a single node from
        // filling the screen and losing context; the wide zoom-out range
        // lets the user shrink even a small graph down to a "constellation
        // of dots" for orientation.
        scrollView.maxMagnification = 2.0
        scrollView.minMagnification = 0.05
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.verticalScrollElasticity = .allowed
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SemanticColors.AppKit.canvasBackground

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
        // Sort edges by id so render order is stable across @Query refetches —
        // otherwise overlapping edges flicker when SwiftData re-orders.
        let sortedEdges = edges.sorted(by: { $0.id.uuidString < $1.id.uuidString })
        let snapshot = GraphSnapshot(nodes: nodes, edges: sortedEdges, categories: categories)
        canvas.update(
            graph: snapshot,
            selectedNodeIDs: selectedNodeIDs,
            modalFocusedNodeID: modalFocusedNodeID,
            edgeVisibility: edgeVisibility,
            layoutMode: layoutMode
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
    private let canvasMultiplier: CGFloat = 1.5
    private var canvasSize: NSSize = .zero
    private var screenObserver: NSObjectProtocol?
    private var isAdjusting = false
    private var hasAppliedInitialZoom = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func commonInit() {
        recomputeCanvasSize()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.recomputeCanvasSize()
            self?.needsLayout = true
        }
    }

    private func recomputeCanvasSize() {
        let largestScreen = NSScreen.screens.max(by: {
            $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }) ?? NSScreen.main
        guard let screen = largestScreen else { return }
        canvasSize = NSSize(
            width: screen.frame.width * canvasMultiplier,
            height: screen.frame.height * canvasMultiplier
        )
    }

    override func tile() {
        super.tile()
        guard !isAdjusting else { return }
        isAdjusting = true
        defer { isAdjusting = false }
        applyCanvasAndMagnification()
    }

    private func applyCanvasAndMagnification() {
        guard let documentView, canvasSize.width > 0, canvasSize.height > 0 else { return }
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
