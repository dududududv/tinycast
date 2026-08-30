import SwiftUI

struct JSONEditorView: View {
    let editor: JSONEditorCoordinator

    @Environment(JSONEditorState.self) private var state

    var body: some View {
        VStack(spacing: 0) {
            JSONSourceEditor(
                input: JSONEditorInput(
                    source: state.source, analysis: state.analysis, revision: state.revision),
                onSourceChange: editor.sourceDidChange,
                onCursorChange: editor.cursorDidChange,
                onReady: editor.editorReady)
            Divider()
            statusBar
        }
        .frame(minWidth: Theme.Size.jsonEditorWindow.width, minHeight: Theme.Size.jsonEditorWindow.height)
        .background(
            VisualEffectView(material: .contentBackground, blending: .behindWindow)
                .ignoresSafeArea()
        )
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

    @ViewBuilder
    private var validationStatus: some View {
        switch state.analysis.validation {
        case .empty:
            Label("Paste or type JSON", systemImage: "curlybraces")
        case .valid:
            Label("Valid JSON", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.Colors.success)
        case .invalid(let issue):
            Button(action: editor.jumpToIssue) {
                Label(
                    String(localized: "Invalid JSON — line \(issue.line), column \(issue.column)"),
                    systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.destructive)
            .help(issue.message)
        }
    }
}
