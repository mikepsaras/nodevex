import CoreGraphics
import Foundation

enum NodeSizingMode: String, CaseIterable, Identifiable {
    case fixed
    case scaledByValue

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fixed: "Uniform size"
        case .scaledByValue: "Size by value"
        }
    }

    var iconName: String {
        switch self {
        case .fixed: "circle.fill"
        case .scaledByValue: "circle.bottomhalf.filled"
        }
    }

    /// Default radius used for fixed mode and as the unit cue across the
    /// rest of the canvas (e.g. the +1pt selection bump).
    static let defaultRadius: CGFloat = 7
    /// Bounds for `.scaledByValue`. Keeps very-low-value nodes hittable and
    /// very-high-value nodes from dominating their neighbors.
    static let scaledMinRadius: CGFloat = 5
    static let scaledMaxRadius: CGFloat = 14

    /// Radius, in pt, for a node with the given intrinsic value (0...1).
    func radius(forValue value: Double) -> CGFloat {
        switch self {
        case .fixed:
            return Self.defaultRadius
        case .scaledByValue:
            let clamped = min(max(value, 0), 1)
            let span = Self.scaledMaxRadius - Self.scaledMinRadius
            return Self.scaledMinRadius + span * CGFloat(clamped)
        }
    }
}
