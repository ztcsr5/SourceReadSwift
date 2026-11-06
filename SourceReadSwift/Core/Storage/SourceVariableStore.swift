import Foundation
import CryptoKit

/// Keeps source-defined preferences in Keychain because some sources also store login tokens there.
final class SourceVariableStore: @unchecked Sendable {
    static let shared = SourceVariableStore(secrets: KeychainSecretStore(service: "com.edc21.SourceReadSwift.source-variables"))
    private let lock = NSLock()
    private let secrets: SecretStoring
    private static let maximumBytes = 256 * 1024

    init(secrets: SecretStoring) { self.secrets = secrets }

    func restore(sourceKey: String) throws -> [String: String] {
        lock.lock(); defer { lock.unlock() }
        guard let text = try secrets.readValue(for: account(sourceKey)) else { return [:] }
        guard text.utf8.count <= Self.maximumBytes else { throw SourceVariableError.tooLarge }
        let values = try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
        return values.filter { Self.isSourceVariable($0.key) }
    }

    func save(_ values: [String: String], sourceKey: String) throws {
        let scoped = values.filter { Self.isSourceVariable($0.key) }
        let bytes = try JSONEncoder().encode(scoped)
        guard bytes.count <= Self.maximumBytes else { throw SourceVariableError.tooLarge }
        lock.lock(); defer { lock.unlock() }
        if scoped.isEmpty { try secrets.removeValue(for: account(sourceKey)) }
        else { try secrets.set(String(decoding: bytes, as: UTF8.self), for: account(sourceKey)) }
    }

    static func isSourceVariable(_ key: String) -> Bool {
        key == "source.variable" || key.hasPrefix("source.variable.")
    }

    private func account(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

private enum SourceVariableError: LocalizedError {
    case tooLarge
    var errorDescription: String? { "源变量超过 256 KiB，未保存到设备。" }
}
