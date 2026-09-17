import Foundation

enum OSSLinkAccess: String, CaseIterable, Codable, Identifiable, Sendable {
    case signed
    case publicRead

    var id: Self { self }
}

enum OSSLinkExpiry: Int, CaseIterable, Codable, Identifiable, Sendable {
    case fifteenMinutes = 900
    case oneHour = 3_600
    case sixHours = 21_600
    case oneDay = 86_400
    case threeDays = 259_200
    case sevenDays = 604_800

    var id: Self { self }
    var interval: TimeInterval { TimeInterval(rawValue) }
}

struct OSSConfiguration: Codable, Equatable, Sendable {
    var endpoint = "https://oss-cn-hangzhou.aliyuncs.com"
    var region = "cn-hangzhou"
    var bucket = ""
    var objectPrefix = "tinycast"
    var linkAccess = OSSLinkAccess.signed
    var linkExpiry = OSSLinkExpiry.oneDay

    func validated() throws -> ValidatedOSSConfiguration {
        let endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = region.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let components = URLComponents(string: endpoint), components.scheme == "https",
            let endpointHost = components.host, !endpointHost.isEmpty,
            components.user == nil, components.password == nil,
            components.query == nil, components.fragment == nil,
            components.path.isEmpty || components.path == "/"
        else { throw OSSConfigurationError.invalidEndpoint }
        guard Self.isValidIdentifier(region) else { throw OSSConfigurationError.invalidRegion }
        guard bucket.count >= 3, bucket.count <= 63, Self.isValidIdentifier(bucket),
            bucket.first != "-", bucket.last != "-"
        else { throw OSSConfigurationError.invalidBucket }

        let objectPrefix =
            objectPrefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "/", omittingEmptySubsequences: true)
            .joined(separator: "/")
        let host = endpointHost.hasPrefix("\(bucket).") ? endpointHost : "\(bucket).\(endpointHost)"
        let authority = components.port.map { "\(host):\($0)" } ?? host
        return ValidatedOSSConfiguration(
            scheme: "https", authority: authority, bucket: bucket, region: region,
            objectPrefix: objectPrefix, linkAccess: linkAccess, linkExpiry: linkExpiry)
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
    }
}

struct ValidatedOSSConfiguration: Equatable, Sendable {
    let scheme: String
    let authority: String
    let bucket: String
    let region: String
    let objectPrefix: String
    let linkAccess: OSSLinkAccess
    let linkExpiry: OSSLinkExpiry
}

enum OSSConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidEndpoint
    case invalidRegion
    case invalidBucket

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return String(localized: "Enter a valid HTTPS OSS endpoint without a path.")
        case .invalidRegion:
            return String(localized: "Enter a valid OSS region, such as cn-hangzhou.")
        case .invalidBucket:
            return String(
                localized: "Enter a valid OSS bucket name using lowercase letters, numbers, and hyphens.")
        }
    }
}
