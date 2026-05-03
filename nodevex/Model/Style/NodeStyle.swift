import Foundation

struct NodeStyle: Codable, Hashable {
    var fillColorHex: String?
    var borderColorHex: String?
    var borderWidth: Double?
    var shape: NodeShape?
}

enum NodeShape: String, Codable {
    case circle
    case roundedRect
    case rect
}
