import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Category.createdAt, order: .reverse) private var categories: [Category]
    @Binding var pendingFocusCategoryID: UUID?
    @FocusState private var focusedRow: UUID?

    var body: some View {
        if categories.isEmpty {
            Text("No categories yet")
                .foregroundStyle(SemanticColors.textSecondary)
                .font(.caption)
        } else {
            ForEach(categories) { category in
                CategoryRowView(
                    category: category,
                    focusedRow: $focusedRow,
                    onDelete: { CategoryCommands.deleteCategory(category, in: modelContext) }
                )
            }
            .onChange(of: pendingFocusCategoryID) { _, newValue in
                guard let newValue else { return }
                focusedRow = newValue
                pendingFocusCategoryID = nil
            }
        }
    }
}

struct CategoryRowView: View {
    @Bindable var category: Category
    @FocusState.Binding var focusedRow: UUID?
    let onDelete: () -> Void

    @State private var isHoveringTrash = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(category.displayColor)
                .frame(width: 10, height: 10)

            TextField("Name", text: $category.name)
                .focused($focusedRow, equals: category.id)
                .textFieldStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(isHoveringTrash ? Color.red : SemanticColors.textSecondary)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringTrash = $0 }
            .help("Delete category")
        }
    }
}
