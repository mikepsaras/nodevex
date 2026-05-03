import Foundation
import CoreGraphics

protocol LayoutStrategy {
    var name: String { get }
    func compute(graph: GraphSnapshot) -> [UUID: CGPoint]
}
