import SwiftUI

struct DocumentToolbar: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                // TODO: create new node via NodeCommands
            } label: {
                Label("New Node", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .help("New Node (⇧⌘N)")
        }
    }
}
