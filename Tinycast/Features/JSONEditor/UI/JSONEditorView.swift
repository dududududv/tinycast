import SwiftUI

struct JSONEditorView: View {
    let state: JSONEditorState
    let editor: JSONEditorCoordinator

    var body: some View {
        VStack(spacing: 0) {
            editorBar
            Divider()
            JSONSourceEditor(
                input: JSONEditorInput(
                    source: state.source, analysis: state.analysis, revision: state.revision),
                onSourceChange: editor.sourceDidChange,
                onCursorChange: editor.cursorDidChange,
                onReady: editor.editorReady,
                onEscape: editor.dismiss)
            .overlay(alignment: .topLeading) { placeholder }
            Divider()
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var editorBar: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            validationStatus
            if state.isWorking { ProgressView().controlSize(.small) }
            Spacer(minLength: Theme.Spacing.lg)
            action("doc.badge.plus", "New", editor.newDocument)
            action("folder", "Open", editor.openDocument)
            action("square.and.arrow.down", "Save", editor.save, disabled: !state.isDirty)
            action(
                "text.alignleft", "Format", editor.format,
                disabled: !state.analysis.validation.isValid)
            action(
                "arrow.down.right.and.arrow.up.left", "Minify", editor.minify,
                disabled: !state.analysis.validation.isValid)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Size.jsonEditorToolbar)
    }

    private func action(
        _ symbol: String, _ label: String, _ perform: @escaping () -> Void,
        disabled: Bool = false
    ) -> some View {
        BarButton(chrome: .rounded, action: perform) {
            Image(systemName: symbol)
                .font(Theme.Typography.bar)
                .symbolRenderingMode(.hierarchical)
                .frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
        }
        .disabled(disabled || state.isWorking)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(label.localized)
        .help(label.localized)
    }

    @ViewBuilder
    private var placeholder: some View {
        if state.source.isEmpty {
            Text("Paste or type JSON")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.leading, 46 + Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xl)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.lg) {
            validationStatus
            if state.isWorking { ProgressView().controlSize(.small) }
            Spacer(minLength: Theme.Spacing.lg)
            Text(String(localized: "Line \(state.cursorLine), Column \(state.cursorColumn)"))
            Text(String(localized: "\(state.lineCount) lines"))
            Text(ByteCountFormatter.string(fromByteCount: Int64(state.byteCount), countStyle: .file))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.jsonEditorStatusBar)
    }

    private var validationStatus: some View {
        Group {
            switch state.analysis.validation {
            case .empty:
                Label("JSON Editor", systemImage: "curlybraces")
            case .valid:
                Label("Valid JSON", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.Colors.success)
            case .invalid(let issue):
                Button(action: editor.jumpToIssue) {
                    Label(
                        String(
                            localized: "Invalid JSON — line \(issue.line), column \(issue.column)"),
                        systemImage: "exclamationmark.triangle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.destructive)
                .help(issue.message)
            }
        }
        .font(Theme.Typography.bar)
        .foregroundStyle(Theme.Colors.textSecondary)
    }
}
