import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Query(sort: \Category.name) private var categories: [Category]

    var body: some View {
        if categories.isEmpty {
            Text("No categories yet")
                .foregroundStyle(SemanticColors.textSecondary)
                .font(.caption)
        } else {
            ForEach(categories) { category in
                Text(category.name)
            }
        }
    }
}
