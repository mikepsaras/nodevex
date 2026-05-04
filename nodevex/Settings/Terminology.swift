import SwiftUI

struct Terminology: Codable, Equatable {
    var inboundSingular: String = "cause"
    var inboundPlural: String = "causes"
    var outboundSingular: String = "effect"
    var outboundPlural: String = "effects"
    var valencePositive: String = "Positive"
    var valenceNegative: String = "Negative"
    var valenceNeutral: String = "Neutral"

    static let `default` = Terminology()

    /// Returns a copy where any empty field is replaced by its default, so the
    /// UI never renders a blank label even if a user clears a Settings field.
    func resolved() -> Terminology {
        let d = Terminology.default
        return Terminology(
            inboundSingular: inboundSingular.isEmpty ? d.inboundSingular : inboundSingular,
            inboundPlural: inboundPlural.isEmpty ? d.inboundPlural : inboundPlural,
            outboundSingular: outboundSingular.isEmpty ? d.outboundSingular : outboundSingular,
            outboundPlural: outboundPlural.isEmpty ? d.outboundPlural : outboundPlural,
            valencePositive: valencePositive.isEmpty ? d.valencePositive : valencePositive,
            valenceNegative: valenceNegative.isEmpty ? d.valenceNegative : valenceNegative,
            valenceNeutral: valenceNeutral.isEmpty ? d.valenceNeutral : valenceNeutral
        )
    }
}

@MainActor
@Observable
final class TerminologyStore {
    private static let key = "terminology.v1"

    var terminology: Terminology {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let value = try? JSONDecoder().decode(Terminology.self, from: data) {
            self.terminology = value
        } else {
            self.terminology = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(terminology) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

private struct TerminologyKey: EnvironmentKey {
    static let defaultValue: Terminology = .default
}

extension EnvironmentValues {
    var terminology: Terminology {
        get { self[TerminologyKey.self] }
        set { self[TerminologyKey.self] = newValue }
    }
}
