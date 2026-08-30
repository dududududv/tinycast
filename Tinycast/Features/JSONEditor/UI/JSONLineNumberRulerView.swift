import AppKit

@MainActor
final class JSONLineNumberRulerView: NSRulerView {
    private weak var editor: JSONEditorTextView?
    private var lineCount = 1

    init(scrollView: NSScrollView, editor: JSONEditorTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 46
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func updateLineCount() {
        guard let editor else { return }
        lineCount = editor.string.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let scrollView else { return }
        let font = JSONSourceEditor.editorFont
        let lineHeight = editor.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize * 1.2
        let inset = editor.textContainerInset.height
        let visibleTop = scrollView.contentView.bounds.minY
        let first = max(Int(floor((visibleTop - inset) / lineHeight)), 0)
        let visibleLines = Int(ceil(bounds.height / lineHeight)) + 2
        let last = min(first + visibleLines, lineCount - 1)
        guard first <= last else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        for line in first...last {
            let label = "\(line + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = inset + CGFloat(line) * lineHeight - visibleTop
                + (lineHeight - size.height) / 2
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - Theme.Spacing.md, y: y),
                withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let editor, let scrollView else { return }
        let point = convert(event.locationInWindow, from: nil)
        let font = JSONSourceEditor.editorFont
        let lineHeight = editor.layoutManager?.defaultLineHeight(for: font) ?? font.pointSize * 1.2
        let contentY = scrollView.contentView.bounds.minY + point.y - editor.textContainerInset.height
        let line = min(max(Int(floor(contentY / lineHeight)), 0), lineCount - 1)
        let range = range(ofLine: line, in: editor.string as NSString)
        editor.setSelectedRange(range)
        editor.scrollRangeToVisible(range)
        editor.window?.makeFirstResponder(editor)
    }

    private func range(ofLine requestedLine: Int, in source: NSString) -> NSRange {
        var range = NSRange(location: 0, length: 0)
        var line = 0
        while line <= requestedLine, range.location < source.length {
            range = source.lineRange(for: NSRange(location: range.location, length: 0))
            if line == requestedLine { return range }
            range.location = NSMaxRange(range)
            line += 1
        }
        return NSRange(location: source.length, length: 0)
    }
}
