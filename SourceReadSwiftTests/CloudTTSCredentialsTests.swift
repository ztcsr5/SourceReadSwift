import XCTest
@testable import SourceReadSwift

private final class InMemorySecretStore: SecretStoring {
    var storage: [String: String] = [:]
    var setCallCount = 0

    func set(_ value: String, for key: String) throws {
        setCallCount += 1
        storage[key] = value
    }

    func value(for key: String) -> String? {
        storage[key]
    }

    func removeValue(for key: String) throws {
        storage.removeValue(forKey: key)
    }
}

final class CloudTTSCredentialsTests: XCTestCase {

    func testConfiguredRequiresAllThreeSecrets() {
        XCTAssertFalse(CloudTTSCredentials().isConfigured)
        XCTAssertFalse(CloudTTSCredentials(appId: "a", apiKey: "b").isConfigured)
        XCTAssertTrue(CloudTTSCredentials(appId: "a", apiKey: "b", apiSecret: "c").isConfigured)
        XCTAssertFalse(CloudTTSCredentials(appId: "  ", apiKey: "b", apiSecret: "c").isConfigured)
    }

    func testSaveLoadRoundTripUsesSingleKeychainItem() throws {
        let secretStore = InMemorySecretStore()
        let store = CloudTTSCredentialsStore(secretStore: secretStore)
        let credentials = CloudTTSCredentials(
            appId: "app",
            apiKey: "key",
            apiSecret: "secret",
            voiceName: "xiaoyan",
            speed: 60,
            volume: 70,
            pitch: 40
        )

        try store.save(credentials)
        XCTAssertEqual(secretStore.storage.count, 1)
        XCTAssertNotNil(secretStore.storage[CloudTTSCredentialsStore.account])

        let loaded = store.load()
        XCTAssertEqual(loaded, credentials)
        XCTAssertTrue(store.isConfigured)
    }

    func testSaveClampsOutOfRangeParameters() throws {
        let store = CloudTTSCredentialsStore(secretStore: InMemorySecretStore())
        let credentials = CloudTTSCredentials(
            appId: "app",
            apiKey: "key",
            apiSecret: "secret",
            speed: 999,
            volume: -20,
            pitch: 120
        )

        try store.save(credentials)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.speed, 100)
        XCTAssertEqual(loaded.volume, 0)
        XCTAssertEqual(loaded.pitch, 100)
    }

    func testClearRemovesCredentials() throws {
        let secretStore = InMemorySecretStore()
        let store = CloudTTSCredentialsStore(secretStore: secretStore)
        try store.save(CloudTTSCredentials(appId: "a", apiKey: "b", apiSecret: "c"))
        try store.clear()

        XCTAssertNil(store.load())
        XCTAssertFalse(store.isConfigured)
        XCTAssertTrue(secretStore.storage.isEmpty)
    }

    func testCorruptPayloadIsIgnored() {
        let secretStore = InMemorySecretStore()
        secretStore.storage[CloudTTSCredentialsStore.account] = "{not-json"
        let store = CloudTTSCredentialsStore(secretStore: secretStore)
        XCTAssertNil(store.load())
        XCTAssertFalse(store.isConfigured)
    }

    func testProtocolConfigTrimsAndDefaultsVoice() {
        let credentials = CloudTTSCredentials(
            appId: " app ",
            apiKey: " key ",
            apiSecret: " secret ",
            voiceName: "",
            speed: 55,
            volume: 65,
            pitch: 45
        )
        let config = credentials.protocolConfig
        XCTAssertEqual(config.appId, "app")
        XCTAssertEqual(config.apiKey, "key")
        XCTAssertEqual(config.apiSecret, "secret")
        XCTAssertEqual(config.voiceName, "xiaoyan")
        XCTAssertEqual(config.speed, 55)
        XCTAssertEqual(config.volume, 65)
        XCTAssertEqual(config.pitch, 45)
    }
}
