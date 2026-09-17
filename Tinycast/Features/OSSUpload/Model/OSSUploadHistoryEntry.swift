import Foundation

struct OSSUploadHistoryEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let fileName: String
    let objectKey: String
    let link: String
    let uploadedAt: Date
    let expiresAt: Date?

    var url: URL? { URL(string: link) }
    var scrollID: String { id.uuidString }

    func isExpired(at date: Date) -> Bool {
        expiresAt.map { $0 <= date } ?? false
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return fileName.localizedCaseInsensitiveContains(query)
            || objectKey.localizedCaseInsensitiveContains(query)
            || link.localizedCaseInsensitiveContains(query)
    }
}
