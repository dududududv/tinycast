import AppKit
import UniformTypeIdentifiers

@MainActor
final class JSONEditorCoordinator {
    let state = JSONEditorState()

    private unowned let core: AppCore
    private weak var textView: JSONEditorTextView?
    private var validationTask: Task<Void, Never>?
    private var operationTask: Task<Void, Never>?
    private var decisionTask: Task<Void, Never>?

    init(core: AppCore) {
        self.core = core
    }

    func show() {
        core.paletteCoordinator.showPalette(mode: .jsonEditor)
        focusEditor()
    }

    func editorReady(_ textView: JSONEditorTextView) {
        self.textView = textView
        textView.onPasteText = { [weak self] text in self?.paste(text) }
        focusEditor()
    }

    private func paste(_ text: String) {
        guard let textView else { return }
        guard !state.isWorking else {
            core.showMessage("正在处理 JSON，请稍后再粘贴", tone: .neutral)
            return
        }
        let source = (state.source as NSString).replacingCharacters(in: textView.selectedRange(), with: text)
        transform(
            { _ in JSONEditorEngine.formatPastedSource(source) }, requiresValidSource: false)
    }

    func sourceDidChange(_ source: String) {
        state.edit(source)
        analyze(source, revision: state.revision)
    }

    func cursorDidChange(line: Int, column: Int) {
        state.moveCursor(line: line, column: column)
    }

    func newDocument() {
        decideReplacement {
            self.state.install("", from: nil)
            self.analyze("", revision: self.state.revision, immediately: true)
            self.focusEditor()
        }
    }

    func openDocument() {
        decideReplacement {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.json, .plainText]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.prompt = String(localized: "Open")
            panel.message = String(localized: "Choose a JSON file to edit.")
            let response = panel.runModal()
            self.restorePalette()
            guard response == .OK, let url = panel.url else { return }
            self.load(url)
        }
    }

    func save() {
        guard let fileURL = state.fileURL else {
            saveAs()
            return
        }
        write(to: fileURL)
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = state.displayName
        panel.prompt = String(localized: "Save")
        panel.message = String(localized: "Save the JSON document.")
        let response = panel.runModal()
        restorePalette()
        guard response == .OK, let url = panel.url else { return }
        write(to: url)
    }

    func format() {
        transform(JSONEditorEngine.prettyPrinted)
    }

    func minify() {
        transform(JSONEditorEngine.minified)
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.source, forType: .string)
        core.showMessage(String(localized: "JSON copied"))
    }

    func jumpToIssue() {
        guard case .invalid(let issue) = state.analysis.validation else { return }
        textView?.moveCaret(to: issue.utf16Offset)
    }

    func dismiss() {
        core.paletteCoordinator.hidePalette()
    }

    func focusEditor() {
        Task { @MainActor [weak textView] in
            await Task.yield()
            guard let textView, let window = textView.window else { return }
            window.makeFirstResponder(textView)
        }
    }

    func handleCommandShortcut(
        _ character: String, modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        switch (character, modifiers) {
        case ("f", [.command]): showFind()
        case ("g", [.command]): find(.nextMatch)
        case ("g", [.command, .shift]): find(.previousMatch)
        case ("n", [.command]): newDocument()
        case ("o", [.command]): openDocument()
        case ("s", [.command]): save()
        case ("s", [.command, .shift]): saveAs()
        case ("f", [.command, .shift]): format()
        case ("m", [.command, .option]): minify()
        default: return false
        }
        return true
    }

    func showFind() {
        find(.showFindInterface)
    }

    private func find(_ action: NSTextFinder.Action) {
        guard let textView else { return }
        if action == .showFindInterface { textView.window?.makeFirstResponder(textView) }
        let item = NSMenuItem()
        item.tag = action.rawValue
        textView.performTextFinderAction(item)
    }

    private func analyze(_ source: String, revision: Int, immediately: Bool = false) {
        validationTask?.cancel()
        validationTask = Task { [weak self] in
            if !immediately {
                do {
                    try await Task.sleep(for: .milliseconds(140))
                } catch {
                    return
                }
            }
            let analysis = await Task.detached(priority: .userInitiated) {
                JSONEditorEngine.analyze(source)
            }.value
            guard !Task.isCancelled else { return }
            self?.state.publish(analysis, for: revision)
        }
    }

    private func transform(
        _ operation: @escaping @Sendable (String) throws -> String,
        requiresValidSource: Bool = true
    ) {
        guard !requiresValidSource || state.analysis.validation.isValid else {
            jumpToIssue()
            return
        }
        let source = state.source
        let revision = state.revision
        operationTask?.cancel()
        state.setWorking(true)
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { state.setWorking(false) }
            do {
                let transformed = try await Task.detached(priority: .userInitiated) {
                    try operation(source)
                }.value
                guard !Task.isCancelled else { return }
                guard state.revision == revision else {
                    core.showMessage("内容已修改，未应用旧的格式化结果")
                    return
                }
                if let textView {
                    textView.replaceAll(with: transformed)
                } else {
                    sourceDidChange(transformed)
                }
            } catch {
                report(error, title: String(localized: "Could not transform JSON"))
            }
        }
    }

    private func decideReplacement(_ action: @escaping @MainActor () -> Void) {
        guard decisionTask == nil else { return }
        decisionTask = Task { [weak self] in
            guard let self else { return }
            defer { decisionTask = nil }
            if state.isDirty {
                let discard = await core.confirm(
                    title: String(localized: "Discard unsaved JSON?"),
                    message: String(localized: "Your changes have not been saved."),
                    symbol: "curlybraces", confirmTitle: String(localized: "Discard"))
                guard discard else { return }
            }
            action()
        }
    }

    private func restorePalette() {
        core.paletteCoordinator.showPalette(mode: .jsonEditor, restoreAnyMode: true)
        focusEditor()
    }

    private func load(_ url: URL) {
        operationTask?.cancel()
        state.setWorking(true)
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { state.setWorking(false) }
            do {
                let source = try await Task.detached(priority: .userInitiated) {
                    try JSONFileService.read(url)
                }.value
                guard !Task.isCancelled else { return }
                state.install(source, from: url)
                analyze(source, revision: state.revision, immediately: true)
                focusEditor()
            } catch {
                report(error, title: String(localized: "Could not open JSON"))
            }
        }
    }

    private func write(to url: URL) {
        let source = state.source
        operationTask?.cancel()
        state.setWorking(true)
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer { state.setWorking(false) }
            do {
                try await Task.detached(priority: .userInitiated) {
                    try JSONFileService.write(source, to: url)
                }.value
                guard !Task.isCancelled, state.source == source else { return }
                state.markSaved(at: url)
                core.showMessage(String(localized: "JSON saved"))
            } catch {
                report(error, title: String(localized: "Could not save JSON"))
            }
        }
    }

    private func report(_ error: Error, title: String) {
        Task { [weak self] in
            await self?.core.showNotice(
                title: title, message: error.localizedDescription,
                symbol: "curlybraces", tone: .danger)
        }
    }
}
