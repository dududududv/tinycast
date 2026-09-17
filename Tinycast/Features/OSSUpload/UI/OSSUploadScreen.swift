import SwiftUI

struct OSSUploadScreen: PaletteScreen {
    enum Row: Equatable, Identifiable {
        case upload
        case history(OSSUploadHistoryEntry)

        var id: String {
            switch self {
            case .upload: return "oss-upload"
            case .history(let entry): return entry.scrollID
            }
        }
    }

    let history: OSSUploadHistoryStore
    let coordinator: OSSUploadCoordinator
    let vm: PaletteState
    let openActions: () -> Void

    private var queryIsEmpty: Bool {
        vm.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var rows: [Row] {
        let entries = history.search(vm.query).map(Row.history)
        return queryIsEmpty ? [.upload] + entries : entries
    }

    var primaryActionTitle: String { "Copy Link" }

    func primaryActionTitle(at selection: Int) -> String {
        if case .upload = row(at: selection) { return "Choose Files" }
        return primaryActionTitle
    }

    func actions(at selection: Int) -> PopoverMenuContent? {
        switch row(at: selection) {
        case .upload:
            return PopoverMenuContent(
                header: "Upload to OSS",
                items: [
                    PopoverMenuItem(
                        title: "Choose Files", systemImage: "folder", shortcut: "↵"
                    ) {
                        coordinator.chooseFilesAndUpload()
                    },
                    PopoverMenuItem(
                        title: "Paste Files", systemImage: "doc.on.clipboard", shortcut: "⌘V"
                    ) {
                        coordinator.uploadPasteboardFiles()
                    },
                    PopoverMenuItem(title: "OSS Settings", systemImage: "gearshape") {
                        coordinator.showSettings()
                    }
                ])
        case .history(let entry):
            return OSSUploadActionsMenu.content(
                entry: entry, coordinator: coordinator, history: history)
        case nil:
            return nil
        }
    }

    func activate(at selection: Int) {
        switch row(at: selection) {
        case .upload: coordinator.chooseFilesAndUpload()
        case .history(let entry): coordinator.copyLink(entry)
        case nil: break
        }
    }

    func secondary(at selection: Int) -> Bool {
        guard case .history(let entry) = row(at: selection) else { return false }
        coordinator.openLink(entry)
        return true
    }

    func delete(at selection: Int) {
        guard case .history(let entry) = row(at: selection) else { return }
        history.remove(entry)
    }

    func deleteAll() {
        guard !history.entries.isEmpty else { return }
        Task { await coordinator.clearHistory() }
    }

    func body(selection: Int, scroll: ScrollIntent) -> AnyView {
        AnyView(content(selection: selection, scroll: scroll))
    }

    @ViewBuilder
    private func content(selection: Int, scroll: ScrollIntent) -> some View {
        let rows = rows
        if rows.isEmpty && !coordinator.isUploading && coordinator.summary.isEmpty {
            EmptyResults(text: "No matching uploads")
        } else {
            OSSUploadView(
                coordinator: coordinator,
                entries: history.search(vm.query), showUploadCard: queryIsEmpty,
                uploadCardSelected: row(at: selection) == .upload,
                selectedID: historyEntry(at: selection)?.id, scroll: scroll,
                isUploading: coordinator.isUploading,
                completedCount: coordinator.completedCount, totalCount: coordinator.totalCount,
                currentFileName: coordinator.currentFileName,
                onSelectUpload: { vm.selection = 0 },
                onChooseFiles: coordinator.chooseFilesAndUpload,
                onPasteFiles: coordinator.uploadPasteboardFiles,
                onUploadActions: {
                    vm.selection = 0
                    openActions()
                },
                onSelectEntry: { entry in
                    if let index = rows.firstIndex(of: .history(entry)) { vm.selection = index }
                },
                onActivateEntry: { entry in coordinator.copyLink(entry) },
                onEntryActions: { entry in
                    if let index = rows.firstIndex(of: .history(entry)) { vm.selection = index }
                    openActions()
                })
        }
    }

    private func row(at selection: Int) -> Row? {
        let rows = rows
        return rows.indices.contains(selection) ? rows[selection] : nil
    }

    private func historyEntry(at selection: Int) -> OSSUploadHistoryEntry? {
        guard case .history(let entry) = row(at: selection) else { return nil }
        return entry
    }
}

@MainActor
enum OSSUploadActionsMenu {
    static func content(
        entry: OSSUploadHistoryEntry, coordinator: OSSUploadCoordinator,
        history: OSSUploadHistoryStore
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: entry.fileName,
            items: [
                PopoverMenuItem(title: "Copy Link", systemImage: "doc.on.doc", shortcut: "↵") {
                    coordinator.copyLink(entry)
                },
                PopoverMenuItem(
                    title: "Open Link", systemImage: "arrow.up.forward.square", shortcut: "⌘↵"
                ) {
                    coordinator.openLink(entry)
                },
                PopoverMenuItem(
                    title: "Delete from History", systemImage: "trash", shortcut: "⌃X",
                    isDestructive: true
                ) {
                    history.remove(entry)
                },
                PopoverMenuItem(
                    title: "Clear History", systemImage: "trash", shortcut: "⌃⇧X",
                    isDestructive: true
                ) {
                    Task { await coordinator.clearHistory() }
                }
            ])
    }
}
