import Foundation
import SwiftData

@Model
final class Node {
    var id: UUID
    var name: String
    var isPinned: Bool
    var pinnedX: Double?
    var pinnedY: Double?

    @Relationship(deleteRule: .nullify, inverse: \Category.nodes)
    var categories: [Category]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.isPinned = false
        self.pinnedX = nil
        self.pinnedY = nil
        self.categories = []
    }
}
