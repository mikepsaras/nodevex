import SwiftUI
import SwiftData

struct NodeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Node.createdAt, order: .reverse) private var nodes: [Node]
    @Binding var pendingFocusNodeID: UUID?
    @FocusState private var focusedRow: UUID?

    var body: some View {
        if nodes.isEmpty {
            Text("No nodes yet")
                .foregroundStyle(SemanticColors.textSecondary)
                .font(.caption)
        } else {
            ForEach(nodes) { node in
                NodeRowView(
                    node: node,
                    focusedRow: $focusedRow,
                    onDelete: { NodeCommands.deleteNode(node, in: modelContext) }
                )
            }
            .onChange(of: pendingFocusNodeID) { _, newValue in
                guard let newValue else { return }
                focusedRow = newValue
                pendingFocusNodeID = nil
            }
        }
    }
}

struct NodeRowView: View {
    @Bindable var node: Node
    @FocusState.Binding var focusedRow: UUID?
    let onDelete: () -> Void

    @State private var isHoveringTrash = false

    var body: some View {
        HStack {
            TextField("Name", text: $node.name)
                .focused($focusedRow, equals: node.id)
                .textFieldStyle(.plain)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(isHoveringTrash ? Color.red : SemanticColors.textSecondary)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringTrash = $0 }
            .help("Delete node")
        }
    }
}
