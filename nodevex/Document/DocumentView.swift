import SwiftUI
import SwiftData

struct DocumentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var nodes: [Node]

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        } detail: {
            ZStack(alignment: .bottomLeading) {
                CanvasView()
                CanvasFooter()
                    .padding(12)
            }
            .toolbar {
                DocumentToolbar(onCreateNode: createNewNode)
            }
        }
        .navigationTitle("NodeVex")
    }

    private func createNewNode() {
        NodeCommands.createNode(name: nextNodeName(), in: modelContext)
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
