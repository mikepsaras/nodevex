import SwiftUI
import SwiftData

struct NodeFocusView: View {
    let node: Node
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var allEdges: [Edge]
    @Query private var allNodes: [Node]

    @State private var creationContext: EdgeCreationContext?

    private var causes: [Edge] {
        allEdges.filter { $0.targetID == node.id }
    }

    private var effects: [Edge] {
        allEdges.filter { $0.sourceID == node.id }
    }

    private func nodeName(_ id: UUID) -> String {
        allNodes.first(where: { $0.id == id })?.name ?? "(missing)"
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 24) {
                if let context = creationContext {
                    EdgeCreationView(
                        focusedNode: node,
                        allNodes: allNodes,
                        context: context,
                        onCancel: { creationContext = nil },
                        onConfirm: { targetID, strength, valence in
                            createEdge(
                                direction: context.direction,
                                otherID: targetID,
                                strength: strength,
                                valence: valence
                            )
                            creationContext = nil
                        }
                    )
                } else {
                    header
                    EdgeSection(
                        title: "Causes",
                        addLabel: "Add cause",
                        edges: causes,
                        relatedNodeID: { $0.sourceID },
                        nodeName: nodeName(_:),
                        onAdd: { creationContext = EdgeCreationContext(direction: .cause) }
                    )
                    EdgeSection(
                        title: "Effects",
                        addLabel: "Add effect",
                        edges: effects,
                        relatedNodeID: { $0.targetID },
                        nodeName: nodeName(_:),
                        onAdd: { creationContext = EdgeCreationContext(direction: .effect) }
                    )
                }
            }
            .padding(32)
            .frame(maxWidth: 520, minHeight: 240)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
        }
        .background {
            Button("Dismiss", action: onDismiss)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
        }
    }

    private var header: some View {
        HStack {
            Text(node.name)
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(SemanticColors.textPrimary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(SemanticColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func createEdge(
        direction: EdgeCreationContext.Direction,
        otherID: UUID,
        strength: Double,
        valence: EdgeValence
    ) {
        switch direction {
        case .cause:
            // Cause: edge points FROM other INTO this node.
            EdgeCommands.createEdge(
                from: otherID,
                to: node.id,
                strength: strength,
                valence: valence,
                in: modelContext
            )
        case .effect:
            // Effect: edge points FROM this node INTO other.
            EdgeCommands.createEdge(
                from: node.id,
                to: otherID,
                strength: strength,
                valence: valence,
                in: modelContext
            )
        }
    }
}

struct EdgeCreationContext: Equatable {
    enum Direction { case cause, effect }
    let direction: Direction
}

private struct EdgeSection: View {
    let title: String
    let addLabel: String
    let edges: [Edge]
    let relatedNodeID: (Edge) -> UUID
    let nodeName: (UUID) -> String
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(SemanticColors.textSecondary)

            if edges.isEmpty {
                Text("None yet")
                    .font(.callout)
                    .foregroundStyle(SemanticColors.textSecondary)
                    .padding(.leading, 4)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(edges) { edge in
                        EdgeRow(edge: edge, name: nodeName(relatedNodeID(edge)))
                    }
                }
            }

            Button(action: onAdd) {
                Label(addLabel, systemImage: "plus")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .padding(.leading, 4)
            .padding(.top, 4)
        }
    }
}

private struct EdgeRow: View {
    let edge: Edge
    let name: String

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(valenceColor)
                .frame(width: 8, height: 8)
            Text(name)
                .foregroundStyle(SemanticColors.textPrimary)
            Spacer()
            Text(strengthLabel)
                .font(.caption)
                .foregroundStyle(SemanticColors.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private var valenceColor: Color {
        switch edge.valence {
        case .positive: SemanticColors.edgePositive
        case .negative: SemanticColors.edgeNegative
        case .neutral: SemanticColors.edgeDefault
        }
    }

    private var strengthLabel: String {
        switch edge.strength {
        case ..<0.34: "weak"
        case ..<0.67: "medium"
        default: "strong"
        }
    }
}

private struct EdgeCreationView: View {
    let focusedNode: Node
    let allNodes: [Node]
    let context: EdgeCreationContext
    let onCancel: () -> Void
    let onConfirm: (UUID, Double, EdgeValence) -> Void

    @State private var pickedNodeID: UUID?
    @State private var strength: Double = 0.5
    @State private var valence: EdgeValence = .neutral
    @State private var searchText: String = ""

    private var directionLabel: String {
        context.direction == .cause ? "cause" : "effect"
    }

    private var availableNodes: [Node] {
        allNodes
            .filter { $0.id != focusedNode.id }
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var pickedNode: Node? {
        guard let pickedNodeID else { return nil }
        return allNodes.first(where: { $0.id == pickedNodeID })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("New \(directionLabel)")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(SemanticColors.textPrimary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(SemanticColors.textSecondary)
            }

            if let pickedNode {
                configureView(for: pickedNode)
            } else {
                pickerView
            }
        }
    }

    private var pickerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Search nodes…", text: $searchText)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(availableNodes) { node in
                        Button {
                            pickedNodeID = node.id
                        } label: {
                            HStack {
                                Text(node.name)
                                    .foregroundStyle(SemanticColors.textPrimary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if availableNodes.isEmpty {
                        Text(searchText.isEmpty ? "No other nodes to connect to" : "No matching nodes")
                            .foregroundStyle(SemanticColors.textSecondary)
                            .font(.callout)
                            .padding()
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func configureView(for picked: Node) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(directionLabel.capitalized):")
                    .foregroundStyle(SemanticColors.textSecondary)
                Text(picked.name)
                    .fontWeight(.semibold)
                    .foregroundStyle(SemanticColors.textPrimary)
                Spacer()
                Button("Change") { pickedNodeID = nil }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Strength")
                        .font(.caption)
                        .foregroundStyle(SemanticColors.textSecondary)
                    Spacer()
                    Text(strengthLabel(strength))
                        .font(.caption)
                        .foregroundStyle(SemanticColors.textSecondary)
                }
                Slider(value: $strength, in: 0...1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Valence")
                    .font(.caption)
                    .foregroundStyle(SemanticColors.textSecondary)
                Picker("Valence", selection: $valence) {
                    Text("Neutral").tag(EdgeValence.neutral)
                    Text("Positive").tag(EdgeValence.positive)
                    Text("Negative").tag(EdgeValence.negative)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Add \(directionLabel)") {
                    onConfirm(picked.id, strength, valence)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func strengthLabel(_ value: Double) -> String {
        switch value {
        case ..<0.34: "weak"
        case ..<0.67: "medium"
        default: "strong"
        }
    }
}
