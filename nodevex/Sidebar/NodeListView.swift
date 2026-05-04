import SwiftUI
import SwiftData

struct NodeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Node.createdAt, order: .reverse) private var nodes: [Node]
    @Binding var editingNodeID: UUID?
    let selectedNodeIDs: Set<UUID>
    let onSelect: (UUID) -> Void

    var body: some View {
        if nodes.isEmpty {
            Text("No nodes yet")
                .foregroundStyle(SemanticColors.textSecondary)
                .font(.caption)
        } else {
            ForEach(nodes) { node in
                NodeRowView(
                    node: node,
                    isSelected: selectedNodeIDs.contains(node.id),
                    isEditing: editingNodeID == node.id,
                    onSelect: { onSelect(node.id) },
                    onCommitEdit: { editingNodeID = nil },
                    onDelete: { NodeCommands.deleteNode(node, in: modelContext) }
                )
            }
        }
    }
}

struct NodeRowView: View {
    @Bindable var node: Node
    let isSelected: Bool
    let isEditing: Bool
    let onSelect: () -> Void
    let onCommitEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHoveringTrash = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack {
            if isEditing {
                TextField("Name", text: $node.name)
                    .focused($isFieldFocused)
                    .textFieldStyle(.plain)
                    .onSubmit(onCommitEdit)
                    .onAppear { isFieldFocused = true }
                    .onChange(of: isFieldFocused) { _, focused in
                        // Click-out commits the edit. Guard on isEditing so we
                        // don't double-fire when the parent already cleared
                        // editingNodeID (e.g., on Return).
                        if !focused && isEditing { onCommitEdit() }
                    }
            } else {
                Text(node.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(isHoveringTrash ? Color.red : SemanticColors.textSecondary)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringTrash = $0 }
            .help("Delete node")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(isSelected ? SemanticColors.nodeFillSelected : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        // simultaneousGesture fires alongside child controls (TextField focus,
        // trash button) so any tap on the row also sets canvas selection.
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
    }
}
