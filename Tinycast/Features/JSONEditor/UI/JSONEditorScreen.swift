import SwiftUI

struct JSONEditorScreen: PaletteScreen {
    let state: JSONEditorState
    let editor: JSONEditorCoordinator

    struct Row: Identifiable {
        let id = "json-editor"
    }

    let rows = [Row()]

    var primaryActionTitle: String { "Copy" }

    func hasPrimaryAction(at selection: Int) -> Bool {
        !state.source.isEmpty
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        PopoverMenuContent(
            header: state.displayName,
            items: [
                PopoverMenuItem(
                    title: "搜索 JSON", systemImage: "magnifyingglass", shortcut: "⌘F",
                    action: editor.showFind),
                PopoverMenuItem(
                    title: "New", systemImage: "doc.badge.plus", shortcut: "⌘N",
                    action: editor.newDocument),
                PopoverMenuItem(
                    title: "Open", systemImage: "folder", shortcut: "⌘O",
                    action: editor.openDocument),
                PopoverMenuItem(
                    title: "Save", systemImage: "square.and.arrow.down", shortcut: "⌘S",
                    action: editor.save),
                PopoverMenuItem(
                    title: "Save JSON As…", systemImage: "square.and.arrow.down.on.square",
                    shortcut: "⇧⌘S", action: editor.saveAs),
                PopoverMenuItem(
                    title: "Format", systemImage: "text.alignleft", shortcut: "⇧⌘F",
                    action: editor.format),
                PopoverMenuItem(
                    title: "Minify", systemImage: "arrow.down.right.and.arrow.up.left",
                    shortcut: "⌥⌘M", action: editor.minify),
                PopoverMenuItem(
                    title: "Copy", systemImage: "doc.on.doc", shortcut: "↵",
                    action: editor.copy)
            ])
    }

    func activate(at selection: Int) {
        editor.copy()
    }

    func secondary(at selection: Int) -> Bool { false }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(JSONEditorView(state: state, editor: editor))
    }
}
