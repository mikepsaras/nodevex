import Foundation

struct EdgeStyle: Codable, Hashable {
    var colorHex: String?
    var lineWidth: Double?
    var dashPattern: [Double]?
    var headShape: ArrowHeadShape?
    var animationSpeed: Double?
}

enum ArrowHeadShape: String, Codable {
    case triangle
    case open
    case diamond
    case circle
}
