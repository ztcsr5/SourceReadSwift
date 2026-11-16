import XCTest
import Security
@testable import SourceReadSwift

final class SourceVariablePersistenceTests: XCTestCase {
    func testSecurityKeychainRestoresLoginAcrossIndependentStoresAndEngines() throws {
        let namespace = UUID().uuidString.lowercased()
        let service = "com.edc21.SourceReadSwift.tests.source-variables.\(namespace)"
        let source = BookSource(bookSourceName: "Keychain fixture",
            bookSourceUrl: "https://\(namespace).keychain.fixture.invalid")
        let sourceKey = LegadoSourceEngine.persistentStateKey(for: source)
        let cleanup = SourceVariableStore(secrets: KeychainSecretStore(service: service))
        defer { XCTAssertNoThrow(try cleanup.save([:], sourceKey: sourceKey)) }

        let first = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil),
            sourceVariables: SourceVariableStore(secrets: KeychainSecretStore(service: service)))
        let initial = first.persistentState(for: source)
        initial.put("fixture-account", for: "source.login.account")
        initial.put(#"{"Authorization":"Bearer synthetic-keychain"}"#, for: "source.loginHeader")
        initial.put("synthetic-field", for: "source.loginHeader.X-Reader-Token")
        XCTAssertNil(initial.persistenceFailure)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var storedItem: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, &storedItem), errSecSuccess)
        let attributes = try XCTUnwrap(storedItem as? [String: Any])
        XCTAssertFalse(try XCTUnwrap(attributes[kSecAttrAccount as String] as? String).isEmpty)

        let reopenedStore = SourceVariableStore(secrets: KeychainSecretStore(service: service))
        let reopenedEngine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), sourceVariables: reopenedStore)
        let restored = reopenedEngine.persistentState(for: source)
        XCTAssertEqual(restored.get("source.login.account"), "fixture-account")
        XCTAssertEqual(restored.get("source.loginHeader"), #"{"Authorization":"Bearer synthetic-keychain"}"#)
        XCTAssertEqual(restored.get("source.loginHeader.X-Reader-Token"), "synthetic-field")
        let request = SourceRequestBuilder().buildPageRequest(source: source, urlText: "/account", persistentValues: restored.snapshot())
        XCTAssertEqual(request.headers["Authorization"], "Bearer synthetic-keychain")
        XCTAssertEqual(request.headers["X-Reader-Token"], "synthetic-field")
    }

    func testLoginHeadersAndAccountSurviveEngineRestartAndLogout() throws {
        let store = SourceVariableStore(secrets: VariableMemorySecrets())
        let source = BookSource(bookSourceName: "Auth", bookSourceUrl: "https://auth.fixture.invalid")
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), sourceVariables: store)
        let state = engine.persistentState(for: source)
        state.put("fixture-user", for: "source.login.account")
        state.put(#"{"Authorization":"Bearer fixture"}"#, for: "source.loginHeader")
        state.put("fixture", for: "source.loginHeader.X-Reader-Token")
        state.put("transient", for: "cookieHeader")
        let restarted = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), sourceVariables: store)
        let restored = restarted.persistentState(for: source)
        XCTAssertEqual(restored.get("source.login.account"), "fixture-user")
        XCTAssertEqual(restored.get("source.loginHeader"), #"{"Authorization":"Bearer fixture"}"#)
        XCTAssertEqual(restored.get("source.loginHeader.X-Reader-Token"), "fixture")
        XCTAssertTrue(restored.get("cookieHeader").isEmpty, "Cookie expiry and domain belong to SourceCookieStore")
        let other = BookSource(bookSourceName: "Other", bookSourceUrl: "https://other.fixture.invalid")
        XCTAssertFalse(restarted.persistentState(for: other).hasLoginState)
        restored.removePrefix("source.login.")
        restored.remove("source.loginHeader")
        restored.removePrefix("source.loginHeader.")
        XCTAssertTrue(try store.restore(sourceKey: LegadoSourceEngine.persistentStateKey(for: source)).isEmpty)
    }

    func testFailedRestoreCannotReplaceTheUnreadableSavedSettings() {
        let secrets = VariableMemorySecrets()
        secrets.shouldFailReads = true
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil),
            sourceVariables: SourceVariableStore(secrets: secrets))
        let state = engine.persistentState(for: BookSource(bookSourceName: "A", bookSourceUrl: "https://a.example"))
        state.put("comic", for: "source.variable")
        XCTAssertEqual(state.get("source.variable"), "comic")
        XCTAssertNotNil(state.persistenceFailure)
        XCTAssertEqual(secrets.writes, 0)
    }

    func testEngineRestartRestoresSourceVariablesButNotChapterTemporaries() {
        let store = SourceVariableStore(secrets: VariableMemorySecrets())
        let source = BookSource(bookSourceName: "A", bookSourceUrl: "https://a.example")
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), sourceVariables: store)
        let state = engine.persistentState(for: source)
        state.put(#"{"mode":"漫画"}"#, for: "source.variable")
        state.put("preference", for: "source.variable.option")
        state.put("chapter-only", for: "chapter.variable")
        let restarted = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), sourceVariables: store)
        XCTAssertEqual(restarted.persistentState(for: source).get("source.variable"), #"{"mode":"漫画"}"#)
        XCTAssertEqual(restarted.persistentState(for: source).get("source.variable.option"), "preference")
        XCTAssertEqual(restarted.persistentState(for: source).get("chapter.variable"), "")
        let other = BookSource(bookSourceName: "B", bookSourceUrl: "https://b.example")
        XCTAssertEqual(restarted.persistentState(for: other).get("source.variable"), "")
    }

    func testRemoveAndRemovePrefixPersistAcrossRestart() throws {
        let store = SourceVariableStore(secrets: VariableMemorySecrets())
        let state = RulePersistentState(saveSourceVariables: { try store.save($0, sourceKey: "source") })
        state.put("comic", for: "source.variable")
        state.put("yes", for: "source.variable.option")
        state.remove("source.variable")
        XCTAssertEqual(try store.restore(sourceKey: "source"), ["source.variable.option": "yes"])
        state.removePrefix("source.variable.")
        XCTAssertTrue(try store.restore(sourceKey: "source").isEmpty)
    }

    func testWriteFailureKeepsSessionStateAndExposesPersistenceError() {
        let state = RulePersistentState(saveSourceVariables: { _ in throw VariableWriteFailure.failed })
        state.put("comic", for: "source.variable")
        XCTAssertEqual(state.get("source.variable"), "comic")
        XCTAssertNotNil(state.persistenceFailure)
    }

    func testOversizedVariableDoesNotReplaceLastSavedPreference() throws {
        let store = SourceVariableStore(secrets: VariableMemorySecrets())
        try store.save(["source.variable": "comic"], sourceKey: "source")
        XCTAssertThrowsError(try store.save(["source.variable": String(repeating: "x", count: 300_000)], sourceKey: "source"))
        XCTAssertEqual(try store.restore(sourceKey: "source")["source.variable"], "comic")
    }

    func testCorruptSavedPreferenceThrowsAndEngineCanStillCreateSessionState() {
        let secrets = VariableMemorySecrets()
        secrets.fallbackValue = "not JSON"
        let store = SourceVariableStore(secrets: secrets)
        XCTAssertThrowsError(try store.restore(sourceKey: "source"))
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), sourceVariables: store)
        let source = BookSource(bookSourceName: "A", bookSourceUrl: "https://a.example")
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable"), "")
    }

    func testExploreActionSurfacesFailedSaveWithoutLosingCurrentChoice() async throws {
        let secrets = VariableMemorySecrets()
        secrets.shouldFailWrites = true
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil),
            sourceVariables: SourceVariableStore(secrets: secrets))
        let source = BookSource(bookSourceName: "A", bookSourceUrl: "https://a.example", exploreUrl: "[]")
        let result = try await engine.performExploreAction(source: source,
            action: "source.setVariable('comic')", inputs: [:]).get()
        XCTAssertTrue(result.message?.contains("保存失败") == true)
        XCTAssertEqual(engine.persistentState(for: source).get("source.variable"), "comic")
    }
}

private enum VariableWriteFailure: Error { case failed }

private final class VariableMemorySecrets: SecretStoring {
    private var values: [String: String] = [:]
    var fallbackValue: String?
    var shouldFailWrites = false
    var shouldFailReads = false
    var writes = 0
    func set(_ value: String, for key: String) throws {
        if shouldFailWrites { throw VariableWriteFailure.failed }
        writes += 1
        values[key] = value
    }
    func value(for key: String) -> String? { values[key] ?? fallbackValue }
    func readValue(for key: String) throws -> String? {
        if shouldFailReads { throw VariableWriteFailure.failed }
        return value(for: key)
    }
    func removeValue(for key: String) throws { values.removeValue(forKey: key) }
}
