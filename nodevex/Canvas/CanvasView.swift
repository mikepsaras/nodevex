import SwiftUI
import SwiftData
import AppKit

struct CanvasView: NSViewRepresentable {
    @Query private var nodes: [Node]

    func makeNSView(context: Context) -> CanvasScrollView {
        let scrollView = CanvasScrollView()
        scrollView.allowsMagnification = true
        scrollView.maxMagnification = 4.0
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SemanticColors.AppKit.canvasBackground

        let canvas = CanvasNSView()
        scrollView.documentView = canvas

        return scrollView
    }

    func updateNSView(_ nsView: CanvasScrollView, context: Context) {
        guard let canvas = nsView.documentView as? CanvasNSView else { return }
        let snapshot = GraphSnapshot(nodes: nodes, edges: [], categories: [])
        canvas.update(graph: snapshot)
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
        let visible = contentView.bounds.size
        guard visible.width > 0, visible.height > 0 else { return }
        let widthRatio = visible.width / canvasSize.width
        let heightRatio = visible.height / canvasSize.height
        let computedMin = min(min(widthRatio, heightRatio), 1.0)
        if abs(minMagnification - computedMin) > 0.001 {
            minMagnification = computedMin
        }
        if !hasAppliedInitialZoom {
            magnification = computedMin
            hasAppliedInitialZoom = true
        } else if magnification < computedMin {
            magnification = computedMin
        }
    }
}
