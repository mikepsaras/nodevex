import Foundation
import SwiftData

@Model
final class Category {
    var id: UUID
    var name: String
    var createdAt: Date
    var colorHex: String?
    var nodes: [Node]

    init(name: String, colorHex: String? = nil) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.colorHex = colorHex
        self.nodes = []
    }
}
