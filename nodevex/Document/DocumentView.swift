import SwiftUI
import SwiftData

struct DocumentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Node.createdAt, order: .reverse) private var nodes: [Node]
    @State private var pendingFocusNodeID: UUID?
    @State private var selectedNodeIDs: Set<UUID> = []
    @State private var focusedNodeID: UUID?
    @State private var edgeVisibility: EdgeVisibilityMode = .animated

    private var focusedNode: Node? {
        guard let focusedNodeID else { return nil }
        return nodes.first(where: { $0.id == focusedNodeID })
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                onCreateNode: createNewNode,
                pendingFocusNodeID: $pendingFocusNodeID
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        } detail: {
            CanvasView(
                selectedNodeIDs: $selectedNodeIDs,
                edgeVisibility: edgeVisibility,
                onNodeFocus: { focusedNodeID = $0 }
            )
            .overlay(alignment: .bottomLeading) {
                CanvasFooter(edgeVisibility: $edgeVisibility)
                    .padding(12)
            }
            .overlay {
                if nodes.isEmpty {
                    EmptyStateCTA(onCreate: createNewNode)
                }
            }
        }
        .navigationTitle("NodeVex")
        .overlay {
            if let focusedNode {
                NodeFocusView(node: focusedNode, onDismiss: { focusedNodeID = nil })
            }
        }
        .background {
            Button("Delete Selected", action: deleteSelectedNodes)
                .keyboardShortcut(.delete, modifiers: [])
                .opacity(0)
                .disabled(selectedNodeIDs.isEmpty || focusedNodeID != nil)
        }
    }

    private func deleteSelectedNodes() {
        let toDelete = nodes.filter { selectedNodeIDs.contains($0.id) }
        for node in toDelete {
            NodeCommands.deleteNode(node, in: modelContext)
        }
        selectedNodeIDs.removeAll()
    }

    private func createNewNode() {
        let node = NodeCommands.createNode(name: nextNodeName(), in: modelContext)
        DispatchQueue.main.async {
            pendingFocusNodeID = node.id
        }
    }

    private func nextNodeName() -> String {
        let existingNumbers = nodes.compactMap { node -> Int? in
            guard node.name.hasPrefix("Node ") else { return nil }
            return Int(node.name.dropFirst("Node ".count))
        }
        let next = (existingNumbers.max() ?? 0) + 1
        return "Node \(next)"
    }
}
