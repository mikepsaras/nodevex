import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(\.modelContext) private var modelContext
    let onCreateNode: () -> Void
    @Binding var pendingFocusNodeID: UUID?
    @State private var pendingFocusCategoryID: UUID?

    var body: some View {
        List {
            Section {
                NodeListView(pendingFocusNodeID: $pendingFocusNodeID)
            } header: {
                HStack {
                    Text("Nodes")
                    Spacer()
                    Button(action: onCreateNode) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .help("New Node (⇧⌘N)")
                }
                .padding(.trailing, 6)
            }
            Section {
                CategoryListView(pendingFocusCategoryID: $pendingFocusCategoryID)
            } header: {
                HStack {
                    Text("Categories")
                    Spacer()
                    Button(action: createCategory) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New Category")
                }
                .padding(.trailing, 6)
            }
        }
        .listStyle(.sidebar)
    }

    private func createCategory() {
        let category = CategoryCommands.createCategory(name: nextCategoryName(), in: modelContext)
        DispatchQueue.main.async {
            pendingFocusCategoryID = category.id
        }
    }

    private func nextCategoryName() -> String {
        let descriptor = FetchDescriptor<Category>()
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        let existingNumbers = existing.compactMap { cat -> Int? in
            guard cat.name.hasPrefix("Category ") else { return nil }
            return Int(cat.name.dropFirst("Category ".count))
        }
        let next = (existingNumbers.max() ?? 0) + 1
        return "Category \(next)"
    }
}
