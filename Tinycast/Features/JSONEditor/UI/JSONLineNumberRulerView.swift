import AppKit

@MainActor
final class JSONLineNumberRulerView: NSRulerView {
    private weak var editor: JSONEditorTextView?

    init(scrollView: NSScrollView, editor: JSONEditorTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 40
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    func updateLineCount() {
        if let editor { editor.lineStarts = JSONEditorEngine.lineStarts(in: editor.string) }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let window else { return }
        let font = JSONSourceEditor.editorFont
        let length = editor.textStorage?.length ?? 0
        let inset = editor.textContainerInset
        let visible = editor.visibleRect
        let probe = NSPoint(
            x: max(visible.minX, inset.width),
            y: max(visible.minY, inset.height) + font.pointSize / 2)
        let visibleIndex = visible.minY <= inset.height
            ? 0 : min(editor.characterIndexForInsertion(at: probe), length)
        let firstLine = JSONEditorEngine.lineIndex(at: visibleIndex, starts: editor.lineStarts)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        for index in firstLine..<min(firstLine + 150, editor.lineStarts.count) {
            let offset = editor.lineStarts[index]
            guard offset <= length else { break }
            let screenRect = editor.firstRect(
                forCharacterRange: NSRange(location: offset, length: 0), actualRange: nil)
            let localRect = convert(window.convertFromScreen(screenRect), from: nil)
            if localRect.minY > bounds.maxY { break }
            let label = "\(index + 1)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - Theme.Spacing.md, y: localRect.minY),
                withAttributes: attributes)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let editor else { return }
        let clickedPoint = editor.convert(event.locationInWindow, from: nil)
        let point = NSPoint(
            x: editor.textContainerInset.width,
            y: max(clickedPoint.y, editor.textContainerInset.height))
        let source = editor.string as NSString
        let offset = min(editor.characterIndexForInsertion(at: point), source.length)
        let range = source.lineRange(for: NSRange(location: offset, length: 0))
        editor.setSelectedRange(range)
        editor.scrollRangeToVisible(range)
        editor.window?.makeFirstResponder(editor)
    }

}
