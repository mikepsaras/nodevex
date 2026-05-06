import SwiftUI

/// Persisted toggles that affect how the canvas renders the deterministic
/// layout. Mirrors the pattern of `AppearanceStore` and `TerminologyStore`:
/// `@Observable` model object owned by `ArachnodeApp`, persisted to
/// UserDefaults, surfaced to the canvas via the SwiftUI environment.
@MainActor
@Observable
final class LayoutPreferenceStore {
    private static let key = "layout-preferences.show-category-regions.v1"

    /// When true, the canvas paints each Voronoi cell as a faint tinted
    /// background fill — useful for visualizing how the partitioner has
    /// divided space among the categories. Default false to keep the
    /// canvas clean by default.
    var showCategoryRegions: Bool {
        didSet {
            UserDefaults.standard.set(showCategoryRegions, forKey: Self.key)
        }
    }

    init() {
        self.showCategoryRegions = UserDefaults.standard.bool(forKey: Self.key)
    }
}

private struct ShowCategoryRegionsKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var showCategoryRegions: Bool {
        get { self[ShowCategoryRegionsKey.self] }
        set { self[ShowCategoryRegionsKey.self] = newValue }
    }
}
