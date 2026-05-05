import SwiftUI
import AppKit

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dim
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Match System"
        case .light: "Light"
        case .dim: "Dim"
        case .dark: "Dark"
        }
    }

    /// nil means "follow system" — `.preferredColorScheme(nil)` clears any
    /// override and lets SwiftUI inherit from the environment. Dim piggybacks
    /// on `.dark` so SwiftUI controls render dark; the canvas background is
    /// what actually changes (see `SemanticColors.AppKit.canvasBackground`).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dim, .dark: .dark
        }
    }
}

private struct AppearanceModeKey: EnvironmentKey {
    static let defaultValue: AppearanceMode = .dim
}

extension EnvironmentValues {
    var appearanceMode: AppearanceMode {
        get { self[AppearanceModeKey.self] }
        set { self[AppearanceModeKey.self] = newValue }
    }
}

/// Reaches up to the hosting `NSWindow` and applies the dim mode tint at
/// three layers: title-bar transparency (so the chrome shows the window
/// background), `window.backgroundColor`, and the content view's CALayer
/// backing color. The CALayer fallback exists because in fullscreen the
/// title bar is auto-hidden and the area above the content view would
/// otherwise paint as bright system white — the layer color guarantees
/// every pixel of the window stays dim. Resets to defaults outside dim
/// mode.
private struct WindowSurfaceConfigurator: NSViewRepresentable {
    let mode: AppearanceMode

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context: Context) {
        let mode = self.mode
        // Defer so the NSView has been attached to its NSWindow by the time
        // we read `view.window`.
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            if mode == .dim {
                window.titlebarAppearsTransparent = true
                window.backgroundColor = SemanticColors.AppKit.dimCanvasBackground
                if let contentView = window.contentView {
                    contentView.wantsLayer = true
                    contentView.layer?.backgroundColor =
                        SemanticColors.AppKit.dimCanvasBackground.cgColor
                }
            } else {
                window.titlebarAppearsTransparent = false
                window.backgroundColor = .windowBackgroundColor
                window.contentView?.layer?.backgroundColor = nil
            }
        }
    }
}

extension View {
    /// In dim mode, tint the NSWindow's title bar, background, and content
    /// view layer to the dim slate. No-op outside dim mode.
    func dimWindowSurface(_ mode: AppearanceMode) -> some View {
        background(WindowSurfaceConfigurator(mode: mode))
    }
}

@MainActor
@Observable
final class AppearanceStore {
    private static let key = "appearance.v1"

    var mode: AppearanceMode {
        didSet { persist() }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key),
           let value = AppearanceMode(rawValue: raw) {
            self.mode = value
        } else {
            self.mode = .dim
        }
    }

    private func persist() {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.key)
    }
}
