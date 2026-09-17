import Foundation

@main
@MainActor
struct OSSUploadTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard !condition() else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static func main() throws {
        testConfiguration()
        testObjectKeys()
        testHistoryEntry()
        testClipboardProtection()
        try testV4Signature()

        print(failures == 0 ? "OSS upload tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func testClipboardProtection() {
        expect(
            OSSUploadService.shouldCopyLinks(
                count: 1, originalChangeCount: 4, currentChangeCount: 4, cancelled: false),
            "an unchanged clipboard receives successful links")
        expect(
            !OSSUploadService.shouldCopyLinks(
                count: 1, originalChangeCount: 4, currentChangeCount: 5, cancelled: false),
            "new clipboard content is preserved")
        expect(
            !OSSUploadService.shouldCopyLinks(
                count: 1, originalChangeCount: 4, currentChangeCount: 4, cancelled: true),
            "cancelling never overwrites the clipboard")
        expect(
            !OSSUploadService.shouldCopyLinks(
                count: 0, originalChangeCount: 4, currentChangeCount: 4, cancelled: false),
            "an entirely failed batch never clears the clipboard")
    }

    static func testConfiguration() {
        var configuration = OSSConfiguration()
        configuration.bucket = "examplebucket"
        configuration.objectPrefix = "/shared//files/"
        let validated = try? configuration.validated()
        expect(
            validated?.authority == "examplebucket.oss-cn-hangzhou.aliyuncs.com",
            "the bucket is added to a standard endpoint")
        expect(validated?.objectPrefix == "shared/files", "the object prefix is normalized")

        configuration.endpoint = "http://oss-cn-hangzhou.aliyuncs.com"
        expect(
            throwsConfigurationError(configuration, .invalidEndpoint),
            "an insecure endpoint is rejected")
        configuration.endpoint = "https://oss-cn-hangzhou.aliyuncs.com"
        configuration.bucket = "Bad_Bucket"
        expect(
            throwsConfigurationError(configuration, .invalidBucket),
            "an invalid bucket is rejected")
    }

    static func testObjectKeys() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 31))!
        let key = OSSObjectKey.make(
            fileName: "report final.pdf", prefix: "tinycast", date: date,
            identifier: "ABCDEF12-3456", calendar: calendar)
        expect(
            key == "tinycast/2026/08/31/abcdef12-report final.pdf",
            "object keys are dated and collision-safe")
    }

    static func testHistoryEntry() {
        let now = Date(timeIntervalSince1970: 1_000)
        let entry = OSSUploadHistoryEntry(
            id: UUID(), fileName: "Quarterly Report.pdf",
            objectKey: "tinycast/2026/08/31/report.pdf",
            link: "https://example.oss-cn-hangzhou.aliyuncs.com/report.pdf",
            uploadedAt: now, expiresAt: now.addingTimeInterval(3_600))
        expect(entry.matches("quarterly"), "history searches file names")
        expect(entry.matches("2026/08/31"), "history searches object keys")
        expect(!entry.matches("photo"), "history excludes unrelated entries")
        expect(!entry.isExpired(at: now), "a fresh signed link is active")
        expect(
            entry.isExpired(at: now.addingTimeInterval(3_601)),
            "a signed history link expires at its configured lifetime")
    }

    static func testV4Signature() throws {
        var configuration = OSSConfiguration()
        configuration.bucket = "examplebucket"
        let validated = try configuration.validated()
        let credentials = OSSCredentials(
            accessKeyID: "test-access", accessKeySecret: "test-secret")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(
                year: 2024, month: 12, day: 3, hour: 3, minute: 44, second: 20))!
        let url = try OSSV4Signer().presignedURL(
            method: .get, objectKey: "folder/hello world.txt", configuration: validated,
            credentials: credentials, expires: 86_400, date: date)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
        expect(
            url.absoluteString.contains("/folder/hello%20world.txt?"),
            "object path segments are encoded without encoding slashes")
        expect(query["x-oss-date"] == "20241203T034420Z", "the signing timestamp is UTC")
        expect(query["x-oss-expires"] == "86400", "the requested expiration is signed")
        expect(
            query["x-oss-signature"]
                == "c95be84a878cd7b7468d1e340b4ef19e3738c4d22b9eee16c6c8e1eb0c6812a3",
            "the V4 signature matches an independent HMAC-SHA256 fixture")
    }

    static func throwsConfigurationError(
        _ configuration: OSSConfiguration, _ expected: OSSConfigurationError
    ) -> Bool {
        do {
            _ = try configuration.validated()
            return false
        } catch let error as OSSConfigurationError {
            return error == expected
        } catch {
            return false
        }
    }
}
