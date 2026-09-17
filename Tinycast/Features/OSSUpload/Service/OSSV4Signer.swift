import CryptoKit
import Foundation

enum OSSSigningError: LocalizedError, Sendable {
    case invalidURL

    var errorDescription: String? {
        String(localized: "Tinycast could not create a valid OSS URL.")
    }
}

struct OSSV4Signer: Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case put = "PUT"
    }

    func presignedURL(
        method: Method,
        objectKey: String,
        configuration: ValidatedOSSConfiguration,
        credentials: OSSCredentials,
        expires: TimeInterval,
        date: Date
    ) throws -> URL {
        let dateStamp = Self.format(date, as: "yyyyMMdd")
        let timestamp = Self.format(date, as: "yyyyMMdd'T'HHmmss'Z'")
        let scope = "\(dateStamp)/\(configuration.region)/oss/aliyun_v4_request"
        let credential = "\(credentials.accessKeyID)/\(scope)"
        let seconds = min(max(Int(expires), 1), OSSLinkExpiry.sevenDays.rawValue)
        let parameters = [
            ("x-oss-additional-headers", "host"),
            ("x-oss-credential", credential),
            ("x-oss-date", timestamp),
            ("x-oss-expires", String(seconds)),
            ("x-oss-signature-version", "OSS4-HMAC-SHA256")
        ]
        let canonicalQuery = Self.query(parameters)
        let encodedObjectKey = Self.percentEncodedPath(objectKey)
        let canonicalURI = "/\(configuration.bucket)/\(encodedObjectKey)"
        let canonicalRequest = [
            method.rawValue,
            canonicalURI,
            canonicalQuery,
            "host:\(configuration.authority)\n",
            "host",
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")
        let stringToSign = [
            "OSS4-HMAC-SHA256", timestamp, scope, Self.sha256Hex(canonicalRequest)
        ].joined(separator: "\n")
        let signature = Self.signature(
            secret: credentials.accessKeySecret, date: dateStamp,
            region: configuration.region, stringToSign: stringToSign)
        let finalQuery = Self.query(parameters + [("x-oss-signature", signature)])
        return try Self.makeURL(
            scheme: configuration.scheme, authority: configuration.authority,
            path: "/\(encodedObjectKey)", query: finalQuery)
    }

    private static func signature(
        secret: String, date: String, region: String, stringToSign: String
    ) -> String {
        let dateKey = hmac(key: Data("aliyun_v4\(secret)".utf8), message: date)
        let regionKey = hmac(key: dateKey, message: region)
        let serviceKey = hmac(key: regionKey, message: "oss")
        let signingKey = hmac(key: serviceKey, message: "aliyun_v4_request")
        return hmac(key: signingKey, message: stringToSign).hex
    }

    private static func hmac(key: Data, message: String) -> Data {
        let code = HMAC<SHA256>.authenticationCode(
            for: Data(message.utf8), using: SymmetricKey(data: key))
        return Data(code)
    }

    private static func sha256Hex(_ value: String) -> String {
        Data(SHA256.hash(data: Data(value.utf8))).hex
    }

    private static func query(_ parameters: [(String, String)]) -> String {
        parameters
            .map {
                (
                    percentEncode($0.0, preservingSlashes: false),
                    percentEncode($0.1, preservingSlashes: false)
                )
            }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")
    }

    static func percentEncodedPath(_ value: String) -> String {
        percentEncode(value, preservingSlashes: true)
    }

    private static func percentEncode(_ value: String, preservingSlashes: Bool) -> String {
        let unreserved = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
        return value.utf8.map { byte in
            if unreserved.contains(byte) || preservingSlashes && byte == 47 {
                return String(UnicodeScalar(byte))
            }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    private static func makeURL(
        scheme: String, authority: String, path: String, query: String
    ) throws -> URL {
        guard let url = URL(string: "\(scheme)://\(authority)\(path)?\(query)") else {
            throw OSSSigningError.invalidURL
        }
        return url
    }

    private static func format(_ date: Date, as format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
