import SwiftUI
import SwiftData

struct DocumentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appearanceMode) private var appearanceMode
    @Query(sort: \Node.createdAt, order: .reverse) private var nodes: [Node]
    @Query private var edges: [Edge]
    @Query private var categories: [Category]
    @State private var editingNodeID: UUID?
    @State private var selectedNodeIDs: Set<UUID> = []
    @State private var focusedNodeID: UUID?
    @State private var edgeVisibility: EdgeVisibilityMode = .hidden
    @State private var nodeSizing: NodeSizingMode = .fixed
    @State private var resetLayoutVersion = 0

    private var focusedNode: Node? {
        guard let focusedNodeID else { return nil }
        return nodes.first(where: { $0.id == focusedNodeID })
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(
                onCreateNode: createNewNode,
                editingNodeID: $editingNodeID,
                selectedNodeIDs: selectedNodeIDs,
                onSelectNode: { id in
                    // Picking a different row also commits any in-progress
                    // edit. Without this the click doesn't defocus the
                    // editing NSTextField, so the user would hit Return
                    // once to commit and a second time to edit the newly
                    // selected node.
                    if editingNodeID != id { editingNodeID = nil }
                    selectedNodeIDs = [id]
                }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 260, max: 400)
        } detail: {
            CanvasView(
                selectedNodeIDs: $selectedNodeIDs,
                edgeVisibility: edgeVisibility,
                nodeSizing: nodeSizing,
                modalFocusedNodeID: focusedNodeID,
                onNodeFocus: { focusedNodeID = $0 },
                appearanceMode: appearanceMode,
                resetLayoutVersion: resetLayoutVersion
            )
            .overlay(alignment: .bottomLeading) {
                CanvasFooter(
                    edgeVisibility: $edgeVisibility,
                    nodeSizing: $nodeSizing,
                    onResetLayout: { resetLayoutVersion += 1 }
                )
                .padding(12)
            }
            .overlay {
                if nodes.isEmpty {
                    EmptyStateCTA(onCreate: createNewNode)
                }
            }
        }
        .navigationTitle("Arachnode")
        .dimWindowSurface(appearanceMode)
        .overlay {
            if let focusedNode {
                NodeFocusView(node: focusedNode, onDismiss: { focusedNodeID = nil })
            }
        }
        .background {
            Button("Delete Selected", action: deleteSelectedNodes)
                .keyboardShortcut(.delete, modifiers: [])
                .opacity(0)
                .disabled(selectedNodeIDs.isEmpty || focusedNodeID != nil || editingNodeID != nil)
        }
        .background {
            Button("Edit Selected", action: editSelectedNode)
                .keyboardShortcut(.return, modifiers: [])
                .opacity(0)
                .disabled(selectedNodeIDs.count != 1 || focusedNodeID != nil || editingNodeID != nil)
        }
        .background {
            Button("Run Graph Analysis", action: runGraphAnalysis)
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .opacity(0)
        }
        .background {
            Button("Seed Stress Test") {
                StressTest.seed500Nodes(in: modelContext)
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .opacity(0)
        }
    }

    private func runGraphAnalysis() {
        let snapshot = GraphSnapshot(nodes: nodes, edges: edges, categories: categories)
        AnalysisRunner.runAll(graph: snapshot)
    }

    private func deleteSelectedNodes() {
        let toDelete = nodes.filter { selectedNodeIDs.contains($0.id) }
        for node in toDelete {
            NodeCommands.deleteNode(node, in: modelContext)
        }
        selectedNodeIDs.removeAll()
    }

    private func editSelectedNode() {
        guard selectedNodeIDs.count == 1, let id = selectedNodeIDs.first else { return }
        editingNodeID = id
    }

    private func createNewNode() {
        let node = NodeCommands.createNode(name: nextNodeName(), in: modelContext)
        selectedNodeIDs = [node.id]
        editingNodeID = node.id
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
