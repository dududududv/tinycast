import AppKit

@MainActor
final class JSONEditorTextView: NSTextView {
    var editorUndoManager: UndoManager?

    override var undoManager: UndoManager? { editorUndoManager }

    func replaceAll(with source: String) {
        let range = NSRange(location: 0, length: (string as NSString).length)
        insertText(source, replacementRange: range)
    }

    func moveCaret(to requestedOffset: Int) {
        let offset = min(max(requestedOffset, 0), (string as NSString).length)
        setSelectedRange(NSRange(location: offset, length: 0))
        scrollRangeToVisible(NSRange(location: offset, length: 0))
        window?.makeFirstResponder(self)
    }
}
