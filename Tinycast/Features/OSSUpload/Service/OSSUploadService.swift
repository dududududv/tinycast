import Foundation

struct OSSUploadResult: Sendable {
    let objectKey: String
    let shareURL: URL
}

enum OSSUploadError: LocalizedError, Sendable {
    case invalidURL
    case notRegularFile
    case fileTooLarge
    case invalidResponse
    case server(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return String(localized: "Tinycast could not create a valid OSS URL.")
        case .notRegularFile:
            return String(localized: "Only regular files can be uploaded to OSS.")
        case .fileTooLarge:
            return String(localized: "This file is larger than the 5 GB PutObject limit.")
        case .invalidResponse:
            return String(localized: "OSS returned an invalid response.")
        case .server(let status, let message):
            if let message, !message.isEmpty {
                return String(localized: "OSS returned HTTP \(status): \(message)")
            }
            return String(localized: "OSS returned HTTP \(status).")
        }
    }
}

struct OSSUploadService: Sendable {
    static func shouldCopyLinks(
        count: Int, originalChangeCount: Int, currentChangeCount: Int, cancelled: Bool
    ) -> Bool {
        count > 0 && !cancelled && originalChangeCount == currentChangeCount
    }

    private let session: URLSession
    private let signer = OSSV4Signer()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    func upload(
        file: URL,
        configuration: ValidatedOSSConfiguration,
        credentials: OSSCredentials,
        date: Date = Date(),
        identifier: String = UUID().uuidString,
        objectDate: Date? = nil,
        imageData: Data? = nil,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }
    ) async throws -> OSSUploadResult {
        let size: Int64
        if let imageData {
            size = Int64(imageData.count)
        } else {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { throw OSSUploadError.notRegularFile }
            size = Int64(values.fileSize ?? 0)
        }
        if size > OSSObjectKey.maximumFileSize {
            throw OSSUploadError.fileTooLarge
        }
        let objectKey = OSSObjectKey.make(
            fileName: file.lastPathComponent, prefix: configuration.objectPrefix,
            date: objectDate ?? date, identifier: identifier)
        let uploadURL = try signer.presignedURL(
            method: .put, objectKey: objectKey, configuration: configuration,
            credentials: credentials, expires: OSSLinkExpiry.fifteenMinutes.interval, date: date)
        var request = URLRequest(url: uploadURL, cachePolicy: .reloadIgnoringLocalCacheData)
        request.httpMethod = OSSV4Signer.Method.put.rawValue
        let delegate = UploadProgress(onProgress: onProgress)
        let data: Data
        let response: URLResponse
        if let imageData {
            (data, response) = try await session.upload(for: request, from: imageData, delegate: delegate)
        } else {
            (data, response) = try await session.upload(for: request, fromFile: file, delegate: delegate)
        }
        try Self.validate(response: response, data: data)

        let shareURL: URL
        switch configuration.linkAccess {
        case .signed:
            shareURL = try signer.presignedURL(
                method: .get, objectKey: objectKey, configuration: configuration,
                credentials: credentials, expires: configuration.linkExpiry.interval, date: Date())
        case .publicRead:
            shareURL = try Self.publicURL(
                objectKey: objectKey, configuration: configuration)
        }
        return OSSUploadResult(objectKey: objectKey, shareURL: shareURL)
    }

    private final class UploadProgress: NSObject, URLSessionTaskDelegate, Sendable {
        let onProgress: @Sendable (Int64, Int64) -> Void

        init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
            self.onProgress = onProgress
        }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
            totalBytesSent: Int64, totalBytesExpectedToSend: Int64
        ) {
            onProgress(totalBytesSent, totalBytesExpectedToSend)
        }
    }

    private static func validate(response: URLResponse, data: Data) throws {
        guard let response = response as? HTTPURLResponse else {
            throw OSSUploadError.invalidResponse
        }
        guard 200..<300 ~= response.statusCode else {
            throw OSSUploadError.server(
                status: response.statusCode, message: xmlMessage(in: data))
        }
    }

    private static func publicURL(
        objectKey: String, configuration: ValidatedOSSConfiguration
    ) throws -> URL {
        let path = OSSV4Signer.percentEncodedPath(objectKey)
        guard let url = URL(string: "\(configuration.scheme)://\(configuration.authority)/\(path)")
        else { throw OSSUploadError.invalidURL }
        return url
    }

    private static func xmlMessage(in data: Data) -> String? {
        guard let text = String(data: data.prefix(4_096), encoding: .utf8),
            let start = text.range(of: "<Message>"),
            let end = text.range(of: "</Message>", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }
}
