import Foundation

enum Propagation {
    struct Result {
        let values: [UUID: Double]
        let iterationsTaken: Int
    }

    static func propagate(initialValues: [UUID: Double], graph: GraphSnapshot, iterations: Int = 100) -> Result {
        // TODO: iterative propagation through edges using strength + valence.
        Result(values: initialValues, iterationsTaken: 0)
    }
}
