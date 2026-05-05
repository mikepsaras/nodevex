import Foundation
import SwiftData

@Model
final class Node {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Intrinsic, user-authored magnitude in 0...1. Drives the optional
    /// value-scaled node size and acts as a pinned root in Propagation.
    var value: Double

    @Relationship(deleteRule: .nullify, inverse: \Category.nodes)
    var categories: [Category]

    init(name: String, value: Double = 0) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.value = value
        self.categories = []
    }
}
