import Foundation
import SwiftData

enum EdgeValence: String, Codable {
    case positive
    case negative
    case neutral
}

@Model
final class Edge {
    var id: UUID
    var sourceID: UUID
    var targetID: UUID
    var strength: Double
    var valence: EdgeValence

    init(sourceID: UUID, targetID: UUID, strength: Double = 0.5, valence: EdgeValence = .neutral) {
        self.id = UUID()
        self.sourceID = sourceID
        self.targetID = targetID
        self.strength = strength
        self.valence = valence
    }
}
