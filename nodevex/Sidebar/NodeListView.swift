import SwiftUI
import SwiftData

struct NodeListView: View {
    @Query(sort: \Node.name) private var nodes: [Node]

    var body: some View {
        if nodes.isEmpty {
            Text("No nodes yet")
                .foregroundStyle(SemanticColors.textSecondary)
                .font(.caption)
        } else {
            ForEach(nodes) { node in
                Text(node.name)
            }
        }
    }
}
