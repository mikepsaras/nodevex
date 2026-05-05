import Foundation
import SwiftData

@Model
final class Node {
    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \Category.nodes)
    var categories: [Category]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.categories = []
    }
}
