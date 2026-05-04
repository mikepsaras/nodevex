import SwiftUI
import SwiftData

@main
struct NodeVexApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([Node.self, Edge.self, Category.self])
        // Ephemeral (in-memory) storage during early development — every app launch
        // starts with an empty graph. Switch to persistent storage when document
        // infrastructure lands per ADR-0025 (DocumentGroup with SwiftData).
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            DocumentView()
        }
        .modelContainer(modelContainer)
    }
}
