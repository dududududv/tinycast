import Foundation

@MainActor
@Observable
final class OSSUploadHistoryStore {
    private static let cap = 200

    private let fileURL: URL
    private(set) var entries: [OSSUploadHistoryEntry]

    init(directory: URL? = nil) {
        fileURL = (directory ?? AppPaths.caches()).appendingPathComponent("oss-upload-history.json")
        if let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([OSSUploadHistoryEntry].self, from: data)
        {
            entries = decoded
        } else {
            entries = []
        }
    }

    func record(
        fileName: String, result: OSSUploadResult, configuration: ValidatedOSSConfiguration,
        uploadedAt: Date = Date()
    ) {
        let expiresAt =
            configuration.linkAccess == .signed
            ? uploadedAt.addingTimeInterval(configuration.linkExpiry.interval) : nil
        entries.insert(
            OSSUploadHistoryEntry(
                id: UUID(), fileName: fileName, objectKey: result.objectKey,
                link: result.shareURL.absoluteString, uploadedAt: uploadedAt,
                expiresAt: expiresAt),
            at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
        persist()
    }

    func search(_ query: String) -> [OSSUploadHistoryEntry] {
        entries.filter { $0.matches(query) }
    }

    func remove(_ entry: OSSUploadHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clearAll() {
        entries = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
