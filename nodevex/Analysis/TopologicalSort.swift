import Foundation

enum TopologicalSort {
    enum SortError: Error {
        case containsCycle
    }

    static func sort(graph: GraphSnapshot) throws -> [UUID] {
        // TODO: Kahn's algorithm or DFS-based topological sort.
        []
    }
}
