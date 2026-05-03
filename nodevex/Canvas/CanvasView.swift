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
        scrollView.backgroundColor = SemanticColors.AppKit.canvasBackground

        let canvas = CanvasNSView(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        scrollView.documentView = canvas

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}
