import XCTest
@testable import SourceReadSwift

final class WebDAVCredentialStoreTests: XCTestCase {
    func testMigrationRemovesPlaintextOnlyAfterSuccessfulKeychainWrite() throws {
        let suite = "WebDAVCredentialStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("test-password", forKey: "webdav.password")
        let secrets = WebDAVTestSecrets()
        secrets.failsWrites = true
        let store = WebDAVCredentialStore(secrets: secrets, defaults: defaults)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(defaults.string(forKey: "webdav.password"), "test-password")
        secrets.failsWrites = false
        XCTAssertEqual(try store.load(), "test-password")
        XCTAssertNil(defaults.object(forKey: "webdav.password"))
        XCTAssertEqual(try store.load(), "test-password")
        try store.save("")
        XCTAssertEqual(try store.load(), "")
    }

    func testUnreadableKeychainCannotBeOverwrittenByLegacyMigration() {
        let suite = "WebDAVCredentialStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("legacy", forKey: "webdav.password")
        let secrets = WebDAVTestSecrets()
        secrets.failsReads = true
        XCTAssertThrowsError(try WebDAVCredentialStore(secrets: secrets, defaults: defaults).load())
        XCTAssertEqual(secrets.writes, 0)
        XCTAssertNotNil(defaults.object(forKey: "webdav.password"))
    }
}

private final class WebDAVTestSecrets: SecretStoring {
    var failsWrites = false
    var failsReads = false
    var writes = 0
    private var values: [String: String] = [:]
    func set(_ value: String, for key: String) throws {
        if failsWrites { throw SecretStoreError.unexpectedStatus(-1) }
        writes += 1
        values[key] = value
    }
    func value(for key: String) -> String? { values[key] }
    func readValue(for key: String) throws -> String? {
        if failsReads { throw SecretStoreError.unexpectedStatus(-1) }
        return values[key]
    }
    func removeValue(for key: String) throws { values.removeValue(forKey: key) }
}
