import AppKit

@MainActor
final class JSONEditorTextView: NSTextView {
    var editorUndoManager: UndoManager?
    var onEscape: (() -> Void)?
    var onPasteText: ((String) -> Void)?
    var lineStarts = [0]

    override func paste(_ sender: Any?) {
        guard !hasMarkedText(), let text = NSPasteboard.general.string(forType: .string),
            let onPasteText
        else {
            super.paste(sender)
            return
        }
        onPasteText(text)
    }

    override var undoManager: UndoManager? { editorUndoManager }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty, !hasMarkedText(), selectedRange().length == 0,
            let character = event.characters, ["{", "[", "}", "]"].contains(character)
        else {
            super.keyDown(with: event)
            return
        }
        let range = selectedRange()
        let prefix = (string as NSString).substring(to: range.location)
        guard !JSONEditorEngine.isInsideString(prefix) else {
            super.keyDown(with: event)
            return
        }
        if character == "}" || character == "]" {
            let source = string as NSString
            if range.location < source.length,
                source.substring(with: NSRange(location: range.location, length: 1)) == character
            {
                setSelectedRange(NSRange(location: range.location + 1, length: 0))
            } else {
                super.keyDown(with: event)
            }
            return
        }
        insertText(character + (character == "{" ? "}" : "]"), replacementRange: range)
        setSelectedRange(NSRange(location: range.location + 1, length: 0))
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), selectedRange().length == 0 else {
            super.insertNewline(sender)
            return
        }
        let range = selectedRange()
        let insertion = JSONEditorEngine.newline(in: string, at: range.location)
        insertText(insertion.text, replacementRange: range)
        setSelectedRange(NSRange(location: range.location + insertion.caret, length: 0))
    }

    override func cancelOperation(_ sender: Any?) {
        if let scrollView = enclosingScrollView, scrollView.isFindBarVisible {
            scrollView.isFindBarVisible = false
            window?.makeFirstResponder(self)
            return
        }
        onEscape?()
    }

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
