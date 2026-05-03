import SwiftUI

struct SidebarView: View {
    let onCreateNode: () -> Void
    @Binding var pendingFocusNodeID: UUID?

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
            Section("Categories") {
                CategoryListView()
            }
        }
        .listStyle(.sidebar)
    }
}
