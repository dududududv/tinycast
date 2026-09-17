import AppKit

@MainActor
@Observable
final class OSSUploadCoordinator {
    private(set) var isUploading = false
    private(set) var completedCount = 0
    private(set) var totalCount = 0
    private(set) var currentFileName: String?
    private(set) var sentBytes: Int64 = 0
    private(set) var expectedBytes: Int64 = 0
    private(set) var summary = ""
    private(set) var failureMessages: [String] = []
    private(set) var retryCount = 0
    private(set) var isCancelling = false
    private(set) var completedLinks: [URL] = []

    private struct UploadItem {
        let file: URL
        var imageData: Data?
        let identifier = UUID().uuidString
        let date = Date()
    }

    @ObservationIgnored private var retryItems: [UploadItem] = []
    @ObservationIgnored private var retryConfiguration: ValidatedOSSConfiguration?
    @ObservationIgnored private var progressID: UUID?

    @ObservationIgnored private let settings: OSSSettingsStore
    @ObservationIgnored private let history: OSSUploadHistoryStore
    @ObservationIgnored private let credentials = OSSCredentialStore()
    @ObservationIgnored private let uploader = OSSUploadService()
    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var uploadTask: Task<Void, Never>?

    init(settings: OSSSettingsStore, history: OSSUploadHistoryStore, core: AppCore) {
        self.settings = settings
        self.history = history
        self.core = core
    }

    func showUpload() {
        core.paletteCoordinator.showPalette(mode: .ossUpload)
    }

    func chooseFilesAndUpload() {
        guard !isUploading else { return }
        guard let context = uploadContext() else { return }

        let restoreUploadScreen = core.paletteCoordinator.isVisible && core.palette.mode == .ossUpload
        if restoreUploadScreen {
            core.paletteCoordinator.hidePalette(restoreFocus: false)
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Upload")
        panel.message = String(localized: "Choose one or more files to upload to OSS.")
        NSApp.activate(ignoringOtherApps: true)
        let accepted = panel.runModal() == .OK
        if restoreUploadScreen { showUpload() }
        guard accepted, !panel.urls.isEmpty else { return }
        start(files: panel.urls, configuration: context.configuration, credentials: context.credentials)
    }

    func uploadPasteboardFiles() {
        guard !isUploading else { return }
        guard let context = uploadContext() else { return }
        let files = pasteboardFiles()
        if files.isEmpty, let image = pasteboardImage() {
            let file = URL(fileURLWithPath: "截图-\(UUID().uuidString.prefix(8)).png")
            start(
                items: [UploadItem(file: file, imageData: image)],
                configuration: context.configuration, credentials: context.credentials)
            return
        }
        guard !files.isEmpty else {
            core.showMessage(
                "请先复制 Finder 文件或截图，再按 ⌘V 上传。", tone: .neutral)
            return
        }
        start(files: files, configuration: context.configuration, credentials: context.credentials)
    }

    private func pasteboardImage() -> Data? {
        if let png = NSPasteboard.general.data(forType: .png) { return png }
        guard let tiff = NSPasteboard.general.data(forType: .tiff),
            let bitmap = NSBitmapImageRep(data: tiff)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    func cancelUpload() {
        guard isUploading else { return }
        isCancelling = true
        uploadTask?.cancel()
    }

    func retryFailed() {
        guard !isUploading, !retryItems.isEmpty, let configuration = retryConfiguration else { return }
        do {
            guard let saved = try credentials.credentials(), saved.isComplete else {
                showSettings()
                return
            }
            start(items: retryItems, configuration: configuration, credentials: saved)
        } catch {
            core.showMessage(error.localizedDescription, tone: .danger)
        }
    }

    func copyCompletedLinks() {
        guard !completedLinks.isEmpty else { return }
        Paster.copyPlainText(completedLinks.map(\.absoluteString).joined(separator: "\n"))
        core.showMessage("本次成功上传的链接已复制")
    }

    func copyLink(_ entry: OSSUploadHistoryEntry) {
        guard !entry.isExpired(at: Date()) else {
            core.showMessage(String(localized: "This signed link has expired."), tone: .danger)
            return
        }
        Paster.copyPlainText(entry.link)
        core.showMessage(String(localized: "OSS link copied."))
    }

    func openLink(_ entry: OSSUploadHistoryEntry) {
        guard !entry.isExpired(at: Date()), let url = entry.url else {
            core.showMessage(String(localized: "This signed link has expired."), tone: .danger)
            return
        }
        core.paletteCoordinator.hidePalette(restoreFocus: false)
        NSWorkspace.shared.open(url)
    }

    func showSettings() {
        core.settingsCoordinator.showSettings(tab: .ossUpload)
    }

    func clearHistory() async {
        guard
            await core.confirm(
                title: String(localized: "Clear OSS upload history?"),
                message: String(localized: "Uploaded objects stay in OSS; only local history is removed."),
                symbol: CommandID.uploadToOSS.sfSymbol,
                confirmTitle: String(localized: "Clear History"))
        else { return }
        history.clearAll()
    }

    func storedAccessKeyID() throws -> String? {
        try credentials.credentials()?.accessKeyID
    }

    func hasStoredCredentials() throws -> Bool {
        try credentials.hasCredentials()
    }

    func saveCredentials(accessKeyID: String, accessKeySecret: String?) throws {
        let secret: String
        if let accessKeySecret, !accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            secret = accessKeySecret
        } else {
            secret = try credentials.credentials()?.accessKeySecret ?? ""
        }
        let updated = OSSCredentials(accessKeyID: accessKeyID, accessKeySecret: secret)
        guard updated.isComplete else { throw OSSCredentialStore.StoreError.invalidEncoding }
        try credentials.setCredentials(updated)
    }

    func removeCredentials() throws {
        try credentials.removeCredentials()
    }

    private func uploadContext() -> (
        configuration: ValidatedOSSConfiguration, credentials: OSSCredentials
    )? {
        do {
            let configuration = try settings.configuration.validated()
            guard let credentials = try credentials.credentials(), credentials.isComplete else {
                showSettings()
                core.showMessage(
                    String(localized: "Add your OSS credentials before uploading."), tone: .neutral)
                return nil
            }
            return (configuration, credentials)
        } catch {
            showSettings()
            core.showMessage(error.localizedDescription, tone: .danger)
            return nil
        }
    }

    private func pasteboardFiles() -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects =
            NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) ?? []
        let urls = objects.compactMap { ($0 as? NSURL).map { $0 as URL } }.filter(\.isFileURL)
        if !urls.isEmpty { return urls }
        guard let text = NSPasteboard.general.string(forType: .string) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            let url = value.hasPrefix("file://") ? URL(string: value) : URL(fileURLWithPath: value)
            guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
            return url
        }
    }

    private func start(
        files: [URL], configuration: ValidatedOSSConfiguration, credentials: OSSCredentials
    ) {
        start(
            items: files.map { UploadItem(file: $0) }, configuration: configuration, credentials: credentials)
    }

    private func start(
        items: [UploadItem], configuration: ValidatedOSSConfiguration, credentials: OSSCredentials
    ) {
        isUploading = true
        isCancelling = false
        completedCount = 0
        totalCount = items.count
        sentBytes = 0
        expectedBytes = 0
        summary = ""
        failureMessages = []
        completedLinks = []
        retryItems = []
        retryCount = 0
        retryConfiguration = configuration
        let clipboardCount = NSPasteboard.general.changeCount
        uploadTask = Task { [weak self] in
            guard let self else { return }
            var links: [URL] = []
            for (index, item) in items.enumerated() {
                if Task.isCancelled {
                    retryItems.append(contentsOf: items[index...])
                    break
                }
                let file = item.file
                let identifier = UUID()
                progressID = identifier
                sentBytes = 0
                expectedBytes = 0
                self.currentFileName = file.lastPathComponent
                do {
                    let result = try await self.uploader.upload(
                        file: file, configuration: configuration, credentials: credentials,
                        identifier: item.identifier, objectDate: item.date, imageData: item.imageData
                    ) { [weak self] sent, expected in
                        Task { @MainActor [weak self] in
                            guard let self, self.progressID == identifier else { return }
                            self.sentBytes = sent
                            self.expectedBytes = expected
                        }
                    }
                    links.append(result.shareURL)
                    self.history.record(
                        fileName: file.lastPathComponent, result: result,
                        configuration: configuration)
                } catch {
                    if Task.isCancelled {
                        retryItems.append(contentsOf: items[index...])
                        break
                    }
                    retryItems.append(item)
                    failureMessages.append("\(file.lastPathComponent)：\(error.localizedDescription)")
                }
                self.completedCount += 1
            }
            self.finish(links: links, clipboardCount: clipboardCount, cancelled: Task.isCancelled)
        }
    }

    private func finish(links: [URL], clipboardCount: Int, cancelled: Bool) {
        isUploading = false
        isCancelling = false
        currentFileName = nil
        progressID = nil
        uploadTask = nil
        retryCount = retryItems.count
        completedLinks = links
        let copied = OSSUploadService.shouldCopyLinks(
            count: links.count, originalChangeCount: clipboardCount,
            currentChangeCount: NSPasteboard.general.changeCount, cancelled: cancelled)
        if copied { Paster.copyPlainText(links.map(\.absoluteString).joined(separator: "\n")) }
        summary =
            cancelled
            ? "已取消，成功 \(links.count) 个，未完成 \(retryCount) 个" : "成功 \(links.count) 个，失败 \(retryCount) 个"
        if copied { summary += " · 链接已复制" } else if !links.isEmpty { summary += " · 可点击复制链接" }
        core.showMessage(summary, tone: failureMessages.isEmpty ? .neutral : .danger)
    }
}
