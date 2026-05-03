import SwiftUI
import SwiftData

@main
struct NodeVexApp: App {
    let modelContainer: ModelContainer = {
        let schema = Schema([Node.self, Edge.self, Category.self])
        let configuration = ModelConfiguration(schema: schema)
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
