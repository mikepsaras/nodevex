import Foundation

enum Centrality {
    static func pageRank(graph: GraphSnapshot, dampingFactor: Double = 0.85, iterations: Int = 50) -> [UUID: Double] {
        // TODO: Power iteration PageRank.
        [:]
    }

    static func betweenness(graph: GraphSnapshot) -> [UUID: Double] {
        // TODO: Brandes' betweenness algorithm.
        [:]
    }

    static func eigenvector(graph: GraphSnapshot, iterations: Int = 50) -> [UUID: Double] {
        // TODO: Power iteration eigenvector centrality.
        [:]
    }
}
