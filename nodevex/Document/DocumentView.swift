import SwiftUI
import SwiftData

struct DocumentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Node.createdAt, order: .reverse) private var nodes: [Node]
    @State private var pendingFocusNodeID: UUID?
    @State private var selectedNodeIDs: Set<UUID> = []

    var body: some View {
        NavigationSplitView {
            SidebarView(
                onCreateNode: createNewNode,
                pendingFocusNodeID: $pendingFocusNodeID
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        } detail: {
            CanvasView(selectedNodeIDs: $selectedNodeIDs)
                .overlay(alignment: .bottomLeading) {
                    CanvasFooter()
                        .padding(12)
                }
                .overlay {
                    if nodes.isEmpty {
                        EmptyStateCTA(onCreate: createNewNode)
                    }
                }
        }
        .navigationTitle("NodeVex")
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
