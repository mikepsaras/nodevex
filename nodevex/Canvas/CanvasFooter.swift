import SwiftUI

struct CanvasFooter: View {
    @Binding var edgeVisibility: EdgeVisibilityMode
    @State private var currentLayoutName = "Force-directed"

    var body: some View {
        HStack(spacing: 8) {
            layoutMenu
            visibilityMenu
        }
    }

    private var layoutMenu: some View {
        Menu {
            Button("Force-directed") { currentLayoutName = "Force-directed" }
            Button("Hierarchical") { currentLayoutName = "Hierarchical" }
        } label: {
            footerLabel(text: currentLayoutName)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(SemanticColors.textSecondary)
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

    private func footerLabel(text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
    }
}
