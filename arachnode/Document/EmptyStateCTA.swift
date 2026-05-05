import SwiftUI

struct EmptyStateCTA: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(SemanticColors.textSecondary)
            VStack(spacing: 6) {
                Text("No nodes yet")
                    .font(.title3)
                    .foregroundStyle(SemanticColors.textPrimary)
                Text("Click + in the sidebar or press ⇧⌘N to create your first node.")
                    .font(.callout)
                    .foregroundStyle(SemanticColors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                onCreate()
            } label: {
                Label("Create your first node", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(maxWidth: 360)
    }
}
