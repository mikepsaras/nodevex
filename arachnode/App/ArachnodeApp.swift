import SwiftUI
import SwiftData

@main
struct ArachnodeApp: App {
    @State private var terminologyStore = TerminologyStore()
    @State private var appearanceStore = AppearanceStore()

    var body: some Scene {
        WindowGroup {
            DocumentView()
                .environment(\.terminology, terminologyStore.terminology.resolved())
                .environment(\.appearanceMode, appearanceStore.mode)
                .preferredColorScheme(appearanceStore.mode.colorScheme)
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
            SettingsView(
                terminologyStore: terminologyStore,
                appearanceStore: appearanceStore
            )
            // Settings is a sibling Scene — it doesn't inherit colorScheme
            // from WindowGroup, so re-apply it here.
            .preferredColorScheme(appearanceStore.mode.colorScheme)
        }
    }
}
