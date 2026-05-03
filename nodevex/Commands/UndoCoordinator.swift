import Foundation
import AppKit

@MainActor
final class UndoCoordinator {
    weak var undoManager: UndoManager?

    init(undoManager: UndoManager? = nil) {
        self.undoManager = undoManager
    }

    // SwiftData's ModelContext provides built-in undo when wired to UndoManager.
    // This coordinator is the surface for explicit named commands when registered manually.
}
