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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CanvasScrollView {
        let scrollView = CanvasScrollView()
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = 4.0
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
        let snapshot = GraphSnapshot(nodes: nodes, edges: edges, categories: [])
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
        let viewportSize = contentView.frame.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { return }
        let widthRatio = viewportSize.width / canvasSize.width
        let heightRatio = viewportSize.height / canvasSize.height
        let computedMin = min(max(widthRatio, heightRatio), 1.0)
        let oldMin = minMagnification
        if abs(minMagnification - computedMin) > 0.01 {
            minMagnification = computedMin
            if computedMin > oldMin && magnification < computedMin {
                magnification = computedMin
            }
        }
        if !hasAppliedInitialZoom {
            magnification = computedMin
            hasAppliedInitialZoom = true
        }
    }
}
