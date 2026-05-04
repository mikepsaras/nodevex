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
                    onCommitEdit: {
                        // Only clear if we're still pointing at this node —
                        // guards against a stale field commit (e.g., a
                        // dismantled InlineEditField firing didEndEditing
                        // after editingNodeID has already advanced).
                        if editingNodeID == node.id { editingNodeID = nil }
                    },
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

    @State private var isHoveringRow = false
    @State private var isHoveringTrash = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if isEditing {
                    InlineEditField(text: $node.name, onCommit: onCommitEdit)
                } else {
                    Text(node.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(isHoveringTrash ? .red : SemanticColors.textSecondary)
            }
            .buttonStyle(.plain)
            .onHover { isHoveringTrash = $0 }
            .help("Delete node")
            .opacity((isHoveringRow || isSelected) ? 1 : 0)
            .animation(.easeInOut(duration: 0.12), value: isHoveringRow)
            .animation(.easeInOut(duration: 0.12), value: isSelected)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? SemanticColors.nodeFillSelected : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .listRowInsets(EdgeInsets(top: 1, leading: 0, bottom: 1, trailing: 0))
        // simultaneousGesture fires alongside child controls (TextField focus,
        // trash button) so any tap on the row also sets canvas selection.
        .contentShape(Rectangle())
        .onHover { isHoveringRow = $0 }
        .simultaneousGesture(TapGesture().onEnded { onSelect() })
    }
}
