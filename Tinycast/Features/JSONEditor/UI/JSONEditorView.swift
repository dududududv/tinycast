import SwiftUI

struct JSONEditorView: View {
    let state: JSONEditorState
    let editor: JSONEditorCoordinator

    var body: some View {
        VStack(spacing: 0) {
            documentBar
            separator
            JSONSourceEditor(
                input: JSONEditorInput(
                    source: state.source, analysis: state.analysis, revision: state.revision),
                wrapsLines: state.wrapsLines,
                onSourceChange: editor.sourceDidChange,
                onCursorChange: editor.cursorDidChange,
                onReady: editor.editorReady,
                onEscape: editor.dismiss
            )
            .overlay(alignment: .topLeading) { placeholder }
            separator
            issueDetails
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var documentBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.plaintext")
                .font(Theme.Typography.bar)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(state.displayName)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if state.isDirty {
                Circle()
                    .fill(Theme.Colors.textTertiary)
                    .frame(width: 5, height: 5)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: Theme.Spacing.lg)
            if state.isWorking { ProgressView().controlSize(.small) }
            actionGroup
        }
        .padding(.horizontal, Theme.Spacing.panelInset)
        .frame(height: Theme.Size.jsonEditorToolbar)
    }

    private var actionGroup: some View {
        HStack(spacing: 0) {
            action("folder", "Open", editor.openDocument)
            action("magnifyingglass", "搜索 ⌘F", editor.showFind)
            action("square.and.arrow.down", "Save", editor.save, disabled: !state.isDirty)
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: Theme.Size.hairline, height: Theme.Size.noteGlyph)
                .padding(.horizontal, Theme.Spacing.xxs)
            action(
                "text.alignleft", "Format", editor.format,
                disabled: !state.analysis.validation.isValid, showsLabel: true)
            action(
                "arrow.down.right.and.arrow.up.left", "Minify", editor.minify,
                disabled: !state.analysis.validation.isValid, showsLabel: true)
            action("doc.on.doc", "Copy", editor.copy, disabled: state.source.isEmpty)
            action(
                "arrow.turn.down.left", state.wrapsLines ? "换行：开" : "换行：关",
                state.toggleWrapping, showsLabel: true)
        }
        .padding(.horizontal, Theme.Spacing.xxs)
        .frosted(in: Capsule())
    }

    private func action(
        _ symbol: String, _ label: String, _ perform: @escaping () -> Void,
        disabled: Bool = false, showsLabel: Bool = false
    ) -> some View {
        BarButton(chrome: .rounded, action: perform) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(Theme.Typography.bar)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: Theme.Size.noteGlyph, height: Theme.Size.noteGlyph)
                if showsLabel {
                    Text(label.localized)
                        .font(Theme.Typography.bar)
                }
            }
            .foregroundStyle(Theme.Colors.textSecondary)
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
                .padding(.leading, 40 + Theme.Spacing.xl)
                .padding(.top, Theme.Spacing.xl)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var statusBar: some View {
        HStack(spacing: Theme.Spacing.md) {
            validationStatus
            if state.byteCount > JSONEditorEngine.highlightLimit {
                Text("大文本 · 已简化高亮")
                    .help("保留编辑、格式化和校验，关闭全文语法着色以减少卡顿。")
            }
            Spacer(minLength: Theme.Spacing.lg)
            Text(String(localized: "Line \(state.cursorLine), Column \(state.cursorColumn)"))
            Text(String(localized: "\(state.lineCount) lines"))
            Text(ByteCountFormatter.string(fromByteCount: Int64(state.byteCount), countStyle: .file))
        }
        .font(.caption)
        .foregroundStyle(Theme.Colors.textTertiary)
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.jsonEditorStatusBar)
    }

    @ViewBuilder
    private var issueDetails: some View {
        if case .invalid(let issue) = state.analysis.validation {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.destructive)
                Text(issue.message)
                    .lineLimit(2)
                    .help(issue.message)
                    .textSelection(.enabled)
                Spacer(minLength: Theme.Spacing.sm)
                Button("定位错误", action: editor.jumpToIssue)
                    .buttonStyle(.plain)
            }
            .font(.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private var validationStatus: some View {
        Group {
            switch state.analysis.validation {
            case .empty:
                Label("JSON Editor", systemImage: "curlybraces")
                    .foregroundStyle(Theme.Colors.textTertiary)
            case .valid:
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.Colors.success)
                    Text("Valid JSON")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            case .invalid(let issue):
                Button(action: editor.jumpToIssue) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.destructive)
                        Text(
                            String(
                                localized:
                                    "Invalid JSON — line \(issue.line), column \(issue.column)")
                        )
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .help(issue.message)
            }
        }
        .font(.caption)
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.Colors.separator)
            .frame(height: Theme.Size.hairline)
    }
}
