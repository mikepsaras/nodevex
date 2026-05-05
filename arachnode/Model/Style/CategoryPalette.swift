import SwiftUI
import AppKit

/// Default palette for auto-assigning category colors. Cycles through 10 hues
/// matching macOS system accent colors, so categories visually distinct against
/// neutral node circles.
enum CategoryPalette {
    static let colorHexes: [String] = [
        "FF3B30",  // red
        "FF9500",  // orange
        "FFCC00",  // yellow
        "34C759",  // green
        "00C7BE",  // teal
        "007AFF",  // blue
        "5856D6",  // indigo
        "AF52DE",  // purple
        "FF2D55",  // pink
        "8E8E93"   // gray
    ]

    static func colorHex(forIndex index: Int) -> String {
        colorHexes[index % colorHexes.count]
    }
}

extension Color {
    init(categoryHex: String) {
        let scanner = Scanner(string: categoryHex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = Double((rgb >> 16) & 0xFF) / 255.0
        let g = Double((rgb >> 8) & 0xFF) / 255.0
        let b = Double(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

extension NSColor {
    convenience init(categoryHex: String) {
        let scanner = Scanner(string: categoryHex)
        var rgb: UInt64 = 0
        scanner.scanHexInt64(&rgb)
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

extension Category {
    var displayColor: Color {
        guard let colorHex else { return SemanticColors.edgeDefault }
        return Color(categoryHex: colorHex)
    }

    var nsDisplayColor: NSColor {
        guard let colorHex else { return SemanticColors.AppKit.edgeDefault }
        return NSColor(categoryHex: colorHex)
    }
}
