import Foundation
import Security

struct OSSCredentialStore: Sendable {
    enum StoreError: LocalizedError {
        case invalidEncoding
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidEncoding:
                return String(localized: "Enter both an AccessKey ID and AccessKey Secret.")
            case .keychain:
                return String(localized: "The login Keychain could not be accessed.")
            }
        }
    }

    private let service: String
    private let account = "credentials"

    init(bundleIdentifier: String? = Bundle.main.bundleIdentifier) {
        service = "\(bundleIdentifier ?? "com.tinycast.app").oss-upload"
    }

    func credentials() throws -> OSSCredentials? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(returningData: true) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        guard let data = result as? Data,
            let credentials = try? JSONDecoder().decode(OSSCredentials.self, from: data)
        else { throw StoreError.invalidEncoding }
        return credentials
    }

    func hasCredentials() throws -> Bool {
        let status = SecItemCopyMatching(query(returningData: false) as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        return true
    }

    func setCredentials(_ credentials: OSSCredentials) throws {
        guard credentials.isComplete,
            let data = try? JSONEncoder().encode(credentials)
        else { throw StoreError.invalidEncoding }
        let lookup = query(returningData: false)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemUpdate(lookup as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addition = lookup
            addition.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addition as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw StoreError.keychain(addStatus) }
        } else if status != errSecSuccess {
            throw StoreError.keychain(status)
        }
    }

    func removeCredentials() throws {
        let status = SecItemDelete(query(returningData: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    private func query(returningData: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if returningData {
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
        }
        return query
    }
}
