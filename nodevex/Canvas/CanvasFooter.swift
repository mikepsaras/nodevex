import SwiftUI

struct CanvasFooter: View {
    @Binding var edgeVisibility: EdgeVisibilityMode

    var body: some View {
        visibilityMenu
    }

    private var visibilityMenu: some View {
        Menu {
            ForEach(EdgeVisibilityMode.allCases) { mode in
                Button {
                    edgeVisibility = mode
                } label: {
                    Label(mode.label, systemImage: mode.iconName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: edgeVisibility.iconName)
                    .font(.caption2)
                Text(edgeVisibility.label)
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
