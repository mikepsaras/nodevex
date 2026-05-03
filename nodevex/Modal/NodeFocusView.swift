import SwiftUI

struct NodeFocusView: View {
    let node: Node
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(node.name)
                .font(.title2)
                .fontWeight(.semibold)

            Text("Causes and effects")
                .foregroundStyle(SemanticColors.textSecondary)
                .font(.caption)

            Rectangle()
                .fill(.quaternary)
                .frame(width: 480, height: 320)
                .overlay {
                    Text("Focus diagram")
                        .foregroundStyle(SemanticColors.textSecondary)
                }
        }
        .padding(32)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 600)
    }
}
