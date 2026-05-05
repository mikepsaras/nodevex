import SwiftUI
import SwiftData

@main
struct ArachnodeApp: App {
    @State private var terminologyStore = TerminologyStore()

    var body: some Scene {
        WindowGroup {
            DocumentView()
                .environment(\.terminology, terminologyStore.terminology.resolved())
        }
        // Ephemeral (in-memory) storage during early development — every app
        // launch starts with an empty graph. Switch to DocumentGroup-based
        // persistence per ADR-0025. `isUndoEnabled: true` wires the
        // mainContext to the SwiftUI environment's undo manager so ⌘Z /
        // ⇧⌘Z roll back inserts, deletes, and property changes.
        .modelContainer(
            for: [Node.self, Edge.self, Category.self],
            inMemory: true,
            isUndoEnabled: true
        )

        Settings {
            SettingsView(store: terminologyStore)
        }
    }
}
