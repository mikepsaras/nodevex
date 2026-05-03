import SwiftUI
import AppKit

struct CanvasView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 4.0
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = SemanticColors.AppKit.canvasBackground

        let canvas = CanvasNSView()
        canvas.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = canvas

        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor)
        ])

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
