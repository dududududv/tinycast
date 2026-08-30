import AppKit
import SwiftUI

struct JSONSourceEditor: NSViewRepresentable {
    let input: JSONEditorInput
    let onSourceChange: (String) -> Void
    let onCursorChange: (Int, Int) -> Void
    let onReady: (JSONEditorTextView) -> Void
    let onEscape: () -> Void

    static let editorFont = NSFont.monospacedSystemFont(
        ofSize: NSFont.systemFontSize, weight: .regular)

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = JSONEditorTextView(usingTextLayoutManager: true)
        Self.configure(textView)
        textView.delegate = context.coordinator
        textView.editorUndoManager = context.coordinator.editorUndoManager
        textView.onEscape = onEscape
        scrollView.documentView = textView

        let ruler = JSONLineNumberRulerView(scrollView: scrollView, editor: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.install(input, resetUndo: false)
        onReady(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView?.onEscape = onEscape
        context.coordinator.update(input)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: JSONSourceEditor
        weak var textView: JSONEditorTextView?
        weak var ruler: JSONLineNumberRulerView?
        let editorUndoManager = UndoManager()

        private var input: JSONEditorInput
        private var isInstalling = false

        init(parent: JSONSourceEditor) {
            self.parent = parent
            input = parent.input
        }

        func install(_ input: JSONEditorInput, resetUndo: Bool) {
            guard let textView else { return }
            self.input = input
            let selection = min(textView.selectedRange().location, (input.source as NSString).length)
            isInstalling = true
            textView.string = input.source
            textView.setSelectedRange(NSRange(location: selection, length: 0))
            applyHighlight(input.analysis, to: textView)
            isInstalling = false
            if resetUndo { editorUndoManager.removeAllActions() }
            ruler?.updateLineCount()
            reportCursor()
        }

        func update(_ next: JSONEditorInput) {
            let previous = input
            input = next
            guard let textView else { return }
            if textView.string != next.source {
                install(next, resetUndo: true)
            } else if previous.analysis != next.analysis {
                applyHighlight(next.analysis, to: textView)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isInstalling, let textView else { return }
            let source = textView.string
            guard source != input.source else { return }
            input = JSONEditorInput(
                source: source, analysis: input.analysis, revision: input.revision + 1)
            parent.onSourceChange(source)
            ruler?.updateLineCount()
            reportCursor()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isInstalling else { return }
            reportCursor()
        }

        private func applyHighlight(
            _ analysis: JSONEditorAnalysis, to textView: JSONEditorTextView
        ) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(JSONSourceEditor.baseAttributes, range: fullRange)
            for token in analysis.tokens where NSMaxRange(token.range) <= storage.length {
                storage.addAttribute(
                    .foregroundColor, value: Self.color(for: token.kind), range: token.range)
            }
            if case .invalid(let issue) = analysis.validation, storage.length > 0 {
                let location = min(issue.utf16Offset, storage.length - 1)
                storage.addAttributes(
                    [
                        .underlineColor: NSColor.systemRed,
                        .underlineStyle: NSUnderlineStyle.single.rawValue
                    ],
                    range: NSRange(location: location, length: 1))
            }
            storage.endEditing()
            textView.typingAttributes = JSONSourceEditor.baseAttributes
        }

        private func reportCursor() {
            guard let textView else { return }
            let source = textView.string as NSString
            let location = min(textView.selectedRange().location, source.length)
            var line = 1
            var lineStart = 0
            var offset = 0
            while offset < location {
                let range = source.lineRange(for: NSRange(location: offset, length: 0))
                guard NSMaxRange(range) <= location else { break }
                line += 1
                lineStart = NSMaxRange(range)
                offset = lineStart
            }
            parent.onCursorChange(line, location - lineStart + 1)
        }

        private static func color(for kind: JSONSyntaxKind) -> NSColor {
            switch kind {
            case .key: return .systemBlue
            case .string: return .systemGreen
            case .number: return .systemPurple
            case .keyword: return .systemOrange
            }
        }
    }

    static func configure(_ textView: NSTextView) {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: Theme.Spacing.xl, height: Theme.Spacing.xl)
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = editorFont
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindPanel = true
        textView.allowsUndo = true
        textView.typingAttributes = baseAttributes
    }

    private static let baseAttributes: [NSAttributedString.Key: Any] = [
        .font: editorFont,
        .foregroundColor: NSColor.labelColor
    ]
}
