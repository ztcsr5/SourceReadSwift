import Foundation

/// Migrates the legacy plaintext password only after Keychain accepts the value.
final class WebDAVCredentialStore {
    private let secrets: SecretStoring
    private let defaults: UserDefaults
    private static let account = "webdav.password"

    init(secrets: SecretStoring = KeychainSecretStore(service: "com.edc21.SourceReadSwift.webdav"),
         defaults: UserDefaults = .standard) {
        self.secrets = secrets
        self.defaults = defaults
    }

    func load() throws -> String {
        if let stored = try secrets.readValue(for: Self.account) {
            defaults.removeObject(forKey: Self.account)
            return stored
        }
        guard let legacy = defaults.string(forKey: Self.account), !legacy.isEmpty else { return "" }
        try save(legacy)
        return legacy
    }

    func save(_ password: String) throws {
        if password.isEmpty { try secrets.removeValue(for: Self.account) }
        else { try secrets.set(password, for: Self.account) }
        defaults.removeObject(forKey: Self.account)
    }
}
