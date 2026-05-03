import SwiftUI

struct CanvasFooter: View {
    @State private var currentLayoutName = "Force-directed"

    var body: some View {
        Menu {
            Button("Force-directed") { currentLayoutName = "Force-directed" }
            Button("Hierarchical") { currentLayoutName = "Hierarchical" }
        } label: {
            HStack(spacing: 4) {
                Text(currentLayoutName)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(SemanticColors.textSecondary)
    }
}
