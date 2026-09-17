import Foundation

struct OSSCredentials: Codable, Equatable, Sendable {
    let accessKeyID: String
    let accessKeySecret: String

    init(accessKeyID: String, accessKeySecret: String) {
        self.accessKeyID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.accessKeySecret = accessKeySecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool { !accessKeyID.isEmpty && !accessKeySecret.isEmpty }
}
