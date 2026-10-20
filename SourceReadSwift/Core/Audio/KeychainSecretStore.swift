import Foundation
import Security

/// Minimal secret storage abstraction so cloud TTS credentials can be tested
/// without touching the real Keychain.
protocol SecretStoring: AnyObject {
    func set(_ value: String, for key: String) throws
    func value(for key: String) -> String?
    func removeValue(for key: String) throws
}

enum SecretStoreError: LocalizedError, Equatable {
    case unexpectedStatus(OSStatus)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain 操作失败（OSStatus \(status)）"
        case .encodingFailed:
            return "凭据编码失败"
        }
    }
}

/// Generic-password Keychain store. Credentials never live in UserDefaults.
final class KeychainSecretStore: SecretStoring {
    private let service: String

    init(service: String = "com.edc21.SourceReadSwift.cloudtts") {
        self.service = service
    }

    func set(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecretStoreError.encodingFailed
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(updateStatus)
        }
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.unexpectedStatus(addStatus)
        }
    }

    func value(for key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func removeValue(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.unexpectedStatus(status)
        }
    }
}
