import AppKit

@MainActor
final class JSONEditorToolbarController: NSObject, WindowChrome, NSToolbarDelegate,
    NSToolbarItemValidation
{
    private static let new = NSToolbarItem.Identifier("JSONNew")
    private static let open = NSToolbarItem.Identifier("JSONOpen")
    private static let save = NSToolbarItem.Identifier("JSONSave")
    private static let format = NSToolbarItem.Identifier("JSONFormat")
    private static let minify = NSToolbarItem.Identifier("JSONMinify")
    private static let copy = NSToolbarItem.Identifier("JSONCopy")

    private weak var editor: JSONEditorCoordinator?
    private weak var state: JSONEditorState?
    private weak var window: NSWindow?

    init(editor: JSONEditorCoordinator, state: JSONEditorState) {
        self.editor = editor
        self.state = state
    }

    func install(in window: NSWindow) {
        self.window = window
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none

        let toolbar = NSToolbar(identifier: "JSONEditorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar
        observe()
    }

    func windowShouldClose(_ window: NSWindow) -> Bool {
        editor?.windowShouldClose(window) ?? true
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            Self.new, Self.open, Self.save, .flexibleSpace,
            Self.format, Self.minify, Self.copy
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch identifier {
        case Self.new:
            return item(
                identifier, title: String(localized: "New"), symbol: "doc.badge.plus",
                action: #selector(new))
        case Self.open:
            return item(
                identifier, title: String(localized: "Open"), symbol: "folder",
                action: #selector(open))
        case Self.save:
            return item(
                identifier, title: String(localized: "Save"), symbol: "square.and.arrow.down",
                action: #selector(save))
        case Self.format:
            return item(
                identifier, title: String(localized: "Format"), symbol: "text.alignleft",
                action: #selector(format))
        case Self.minify:
            return item(
                identifier, title: String(localized: "Minify"),
                symbol: "arrow.down.right.and.arrow.up.left", action: #selector(minify))
        case Self.copy:
            return item(
                identifier, title: String(localized: "Copy"), symbol: "doc.on.doc",
                action: #selector(copyDocument))
        default:
            return nil
        }
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        guard let state, !state.isWorking else { return false }
        switch item.itemIdentifier {
        case Self.save: return state.isDirty
        case Self.format, Self.minify: return state.analysis.validation.isValid
        case Self.copy: return !state.source.isEmpty
        default: return true
        }
    }

    @objc private func new() { editor?.newDocument() }
    @objc private func open() { editor?.openDocument() }
    @objc private func save() { editor?.save() }
    @objc private func format() { editor?.format() }
    @objc private func minify() { editor?.minify() }
    @objc private func copyDocument() { editor?.copy() }

    private func item(
        _ identifier: NSToolbarItem.Identifier, title: String, symbol: String, action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = title
        item.paletteLabel = title
        item.toolTip = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.target = self
        item.action = action
        item.autovalidates = true
        return item
    }

    private func observe() {
        guard let state else { return }
        withObservationTracking {
            sync(state)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func sync(_ state: JSONEditorState) {
        window?.title = state.displayName
        window?.representedURL = state.fileURL
        window?.isDocumentEdited = state.isDirty
        window?.toolbar?.validateVisibleItems()
        _ = state.analysis
        _ = state.isWorking
    }
}
