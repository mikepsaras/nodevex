import SwiftUI
import AppKit

enum SemanticColors {
    static var canvasBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var nodeFill: Color { Color(nsColor: .controlBackgroundColor) }
    static var nodeBorder: Color { Color(nsColor: .separatorColor) }
    static var nodeFillSelected: Color { Color.accentColor.opacity(0.15) }
    static var edgeDefault: Color { Color(nsColor: .tertiaryLabelColor) }
    static var edgePositive: Color { .green }
    static var edgeNegative: Color { .red }
    static var textPrimary: Color { Color(nsColor: .labelColor) }
    static var textSecondary: Color { Color(nsColor: .secondaryLabelColor) }
    static var divider: Color { Color(nsColor: .separatorColor) }

    enum AppKit {
        static var canvasBackground: NSColor { .windowBackgroundColor }
        /// Dim mode: a noticeably lighter slate than system dark, so the canvas
        /// (which dominates the window) reads as "muted" rather than near-black.
        static let dimCanvasBackground: NSColor = NSColor(
            srgbRed: 0x2E / 255.0,
            green: 0x2E / 255.0,
            blue: 0x32 / 255.0,
            alpha: 1
        )
        static func canvasBackground(for mode: AppearanceMode) -> NSColor {
            mode == .dim ? dimCanvasBackground : canvasBackground
        }
        static var nodeFill: NSColor { .controlBackgroundColor }
        static var nodeFillSelected: NSColor { .controlAccentColor.withAlphaComponent(0.15) }
        static var nodeBorder: NSColor { .separatorColor }
        static var nodeBorderSelected: NSColor { .controlAccentColor }
        static var edgeDefault: NSColor { .tertiaryLabelColor }
        static var edgePositive: NSColor { .systemGreen }
        static var edgeNegative: NSColor { .systemRed }
        static var textPrimary: NSColor { .labelColor }
        static var textSecondary: NSColor { .secondaryLabelColor }
        static var divider: NSColor { .separatorColor }
    }
}
