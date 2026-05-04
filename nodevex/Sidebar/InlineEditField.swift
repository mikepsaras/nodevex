import SwiftUI
import AppKit

/// Borderless, transparent NSTextField wrapped for inline rename in lists.
/// SwiftUI's TextField with `.textFieldStyle(.plain)` still renders subtle
/// chrome (background fill, focus ring) on macOS — this drops straight to
/// NSTextField with everything turned off so the only visible edit affordance
/// is the system-blue insertion cursor.
///
/// Auto-focuses and selects-all on first appearance so typing immediately
/// replaces the existing name. Return / Escape / focus-loss all commit.
struct InlineEditField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.bezelStyle = .squareBezel
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.stringValue = text

        // Belt-and-suspenders: cell properties on NSTextFieldCell don't
        // always inherit cleanly from the field, so configure them too.
        if let cell = field.cell as? NSTextFieldCell {
            cell.isBordered = false
            cell.isBezeled = false
            cell.drawsBackground = false
            cell.backgroundColor = .clear
            cell.focusRingType = .none
            cell.usesSingleLineMode = true
            cell.lineBreakMode = .byTruncatingTail
        }

        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if context.coordinator.shouldFocus {
            context.coordinator.shouldFocus = false
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                // The field editor is a window-shared NSTextView that AppKit
                // installs into the field on focus. Its drawsBackground
                // defaults to true and paints over the row tint — that's the
                // "ugly box". Force it transparent here, after focus is set.
                if let editor = nsView.currentEditor() as? NSTextView {
                    editor.drawsBackground = false
                    editor.backgroundColor = .clear
                    let length = (editor.string as NSString).length
                    editor.selectedRange = NSRange(location: length, length: 0)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineEditField
        var shouldFocus = true
        // Guard against committing twice when Return triggers both
        // doCommandBy(insertNewline:) and the subsequent didEndEditing.
        private var didCommit = false

        init(parent: InlineEditField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard !didCommit else { return }
            didCommit = true
            parent.onCommit()
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.cancelOperation(_:)):
                guard !didCommit else { return true }
                didCommit = true
                parent.onCommit()
                return true
            default:
                return false
            }
        }
    }
}
