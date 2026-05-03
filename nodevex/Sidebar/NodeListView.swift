import SwiftUI
import SwiftData

struct NodeListView: View {
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
                NodeRowView(node: node, focusedRow: $focusedRow)
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

    var body: some View {
        TextField("Name", text: $node.name)
            .focused($focusedRow, equals: node.id)
            .textFieldStyle(.plain)
    }
}
