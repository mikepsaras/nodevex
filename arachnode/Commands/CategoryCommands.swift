import Foundation
import SwiftData

enum CategoryCommands {
    @discardableResult
    static func createCategory(name: String, in context: ModelContext) -> Category {
        let descriptor = FetchDescriptor<Category>()
        let count = (try? context.fetchCount(descriptor)) ?? 0
        let colorHex = CategoryPalette.colorHex(forIndex: count)
        let category = Category(name: name, colorHex: colorHex)
        context.insert(category)
        return category
    }

    /// Deletes a category. Node.categories uses @Relationship(deleteRule: .nullify),
    /// so SwiftData drops the assignment from any node that referenced this category.
    static func deleteCategory(_ category: Category, in context: ModelContext) {
        context.delete(category)
    }

    static func toggleAssignment(node: Node, category: Category) {
        if node.categories.contains(where: { $0.id == category.id }) {
            node.categories.removeAll(where: { $0.id == category.id })
        } else {
            node.categories.append(category)
        }
    }
}
