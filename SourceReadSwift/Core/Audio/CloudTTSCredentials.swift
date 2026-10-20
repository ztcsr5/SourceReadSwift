import Foundation

/// User-editable iFlyTek TTS credentials and voice parameters.
struct CloudTTSCredentials: Codable, Equatable, Sendable {
    var appId: String
    var apiKey: String
    var apiSecret: String
    var voiceName: String
    var speed: Int
    var volume: Int
    var pitch: Int

    init(
        appId: String = "",
        apiKey: String = "",
        apiSecret: String = "",
        voiceName: String = "xiaoyan",
        speed: Int = 50,
        volume: Int = 50,
        pitch: Int = 50
    ) {
        self.appId = appId
        self.apiKey = apiKey
        self.apiSecret = apiSecret
        self.voiceName = voiceName
        self.speed = speed
        self.volume = volume
        self.pitch = pitch
    }

    var isConfigured: Bool {
        !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !apiSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var protocolConfig: CloudTTSProtocol.XunfeiConfig {
        CloudTTSProtocol.XunfeiConfig(
            appId: appId.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            apiSecret: apiSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            voiceName: voiceName.isEmpty ? "xiaoyan" : voiceName,
            speed: min(max(speed, 0), 100),
            volume: min(max(volume, 0), 100),
            pitch: min(max(pitch, 0), 100)
        )
    }

    func clamped() -> CloudTTSCredentials {
        var copy = self
        copy.speed = min(max(speed, 0), 100)
        copy.volume = min(max(volume, 0), 100)
        copy.pitch = min(max(pitch, 0), 100)
        return copy
    }
}

/// Persists the credential blob as a single Keychain item to avoid partial
/// writes (for example appId saved but apiSecret missing).
final class CloudTTSCredentialsStore {
    static let account = "xunfei-credentials"

    private let secretStore: SecretStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(secretStore: SecretStoring = KeychainSecretStore()) {
        self.secretStore = secretStore
    }

    func load() -> CloudTTSCredentials? {
        guard let raw = secretStore.value(for: Self.account),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(CloudTTSCredentials.self, from: data)
    }

    func save(_ credentials: CloudTTSCredentials) throws {
        let data = try encoder.encode(credentials.clamped())
        guard let raw = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.encodingFailed
        }
        try secretStore.set(raw, for: Self.account)
    }

    func clear() throws {
        try secretStore.removeValue(for: Self.account)
    }

    var isConfigured: Bool {
        load()?.isConfigured == true
    }
}
