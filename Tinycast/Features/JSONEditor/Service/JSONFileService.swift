import Foundation

enum JSONFileService {
    nonisolated static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    nonisolated static func write(_ source: String, to url: URL) throws {
        try source.write(to: url, atomically: true, encoding: .utf8)
    }
}
