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

    private var savedSource = ""

    var isDirty: Bool { source != savedSource }
    var displayName: String { fileURL?.lastPathComponent ?? String(localized: "Untitled.json") }
    var byteCount: Int { source.utf8.count }

    var lineCount: Int {
        source.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
    }

    func edit(_ source: String) {
        self.source = source
        revision += 1
    }

    func install(_ source: String, from fileURL: URL?) {
        self.source = source
        self.fileURL = fileURL
        savedSource = source
        revision += 1
        cursorLine = 1
        cursorColumn = 1
    }

    func markSaved(at fileURL: URL) {
        self.fileURL = fileURL
        savedSource = source
    }

    func revert() {
        source = savedSource
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
