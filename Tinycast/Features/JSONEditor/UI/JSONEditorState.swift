import Foundation

@MainActor
@Observable
final class JSONEditorState {
    private(set) var source = ""
    private(set) var analysis = JSONEditorAnalysis(validation: .empty, tokens: [])
    private(set) var fileURL: URL?
    private(set) var revision = 0
    private(set) var cursorLine = 1
    private(set) var cursorColumn = 1
    private(set) var isWorking = false
    private(set) var wrapsLines = false

    func toggleWrapping() {
        wrapsLines.toggle()
    }

    private var savedSource = ""

    private(set) var isDirty = false
    var displayName: String { fileURL?.lastPathComponent ?? String(localized: "Untitled.json") }
    private(set) var byteCount = 0
    private(set) var lineCount = 1

    private func updateMetrics() {
        byteCount = source.utf8.count
        lineCount = source.utf8.reduce(into: 1) { count, byte in
            if byte == 10 { count += 1 }
        }
    }

    func edit(_ source: String) {
        self.source = source
        isDirty = source != savedSource
        updateMetrics()
        revision += 1
    }

    func install(_ source: String, from fileURL: URL?) {
        self.source = source
        updateMetrics()
        self.fileURL = fileURL
        savedSource = source
        isDirty = false
        revision += 1
        cursorLine = 1
        cursorColumn = 1
    }

    func markSaved(at fileURL: URL) {
        self.fileURL = fileURL
        savedSource = source
        isDirty = false
    }

    func revert() {
        source = savedSource
        isDirty = false
        updateMetrics()
        revision += 1
    }

    func publish(_ analysis: JSONEditorAnalysis, for revision: Int) {
        guard self.revision == revision else { return }
        self.analysis = analysis
    }

    func moveCursor(line: Int, column: Int) {
        cursorLine = line
        cursorColumn = column
    }

    func setWorking(_ isWorking: Bool) {
        self.isWorking = isWorking
    }
}

struct JSONEditorInput: Equatable {
    let source: String
    let analysis: JSONEditorAnalysis
    let revision: Int
}
