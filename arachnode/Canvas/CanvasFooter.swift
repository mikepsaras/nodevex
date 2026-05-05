import SwiftUI

struct CanvasFooter: View {
    @Binding var edgeVisibility: EdgeVisibilityMode
    let onResetLayout: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            visibilityMenu
            relayoutButton
        }
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

    private var relayoutButton: some View {
        Button(action: onResetLayout) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption2)
                Text("Re-layout")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(SemanticColors.textSecondary)
        .help("Reshuffle node positions and resettle")
    }
}
