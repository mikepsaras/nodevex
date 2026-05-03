import SwiftUI

struct DocumentToolbar: ToolbarContent {
    let onCreateNode: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                onCreateNode()
            } label: {
                Label("New Node", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("New Node (⇧⌘N)")
        }
    }
}
