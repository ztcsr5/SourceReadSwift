import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceLoginCacheCompatibilityTests: XCTestCase {
    private var rootURL: URL!
    private var secrets: LoginCacheMemorySecrets!
    private let sourceURL = "https://login-cache.fixture.invalid/generic-source"

    override func setUpWithError() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        secrets = LoginCacheMemorySecrets()
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: rootURL.path) { try FileManager.default.removeItem(at: rootURL) }
    }

    func testBareAESUsesECBAndEncryptReturnsBytes() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        let result = try runtime.evaluate("""
        var cipher = java.createSymmetricCrypto('AES', '0123456789abcdef');
        var bytes = cipher.encrypt('synthetic login fixture');
        [Array.isArray(bytes), java.base64Encode(bytes), cipher.encryptBase64('synthetic login fixture'),
         cipher.decryptStr(bytes)].join('|');
        """).get()
        let encoded = "IGW3aw/GhuyyEsysA2qB1YIqm5r4qyPtrjHXNFF6+OE="
        XCTAssertEqual(result, "true|\(encoded)|\(encoded)|synthetic login fixture")
    }

    func testAuthoredCacheWritesReplaceOldTokenAndRemovedFields() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        try writeLogin(["token": "old-token", "removed": "old-field"], runtime: runtime)
        _ = try runtime.evaluate("source.setLoginInfo('token', 'typed-form'); 'done'").get()
        try writeLogin(["token": "new-token", "账号": "合成账号"], runtime: runtime)
        XCTAssertEqual(try loginFields(runtime), ["token": "new-token", "账号": "合成账号"])
        XCTAssertEqual(try runtime.evaluate("source.getLoginInfoMap().get('token')").get(), "new-token")
    }

    func testLoginAndMirrorSurviveIndependentCacheAndVariableStoreReload() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        try writeLogin(["token": "saved-token", "account": "saved-account"], runtime: runtime)
        let saved = try savedVariables()
        XCTAssertFalse(saved["source.loginCacheMirror", default: ""].isEmpty)
        XCTAssertFalse(saved["source.loginCacheMirror", default: ""].contains("saved-token"))
        let reopened = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        XCTAssertEqual(try loginFields(reopened), ["token": "saved-token", "account": "saved-account"])
    }

    func testOrdinaryReadPreservesLaterFormValuesAcrossRestart() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        try writeLogin(["token": "cached-token", "account": "cached-account"], runtime: runtime)
        _ = try runtime.evaluate("source.getLoginInfoMap().put('account', 'new-form'); 'done'").get()
        XCTAssertEqual(try loginFields(runtime)["account"], "new-form")
        let reopened = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        XCTAssertEqual(try loginFields(reopened), ["token": "cached-token", "account": "new-form"])
    }

    func testFirstCacheReadFillsMissingFieldsWithoutReplacingExistingForm() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        let runtime = try makeRuntime(store)
        _ = try runtime.evaluate("source.setLoginInfo('account', 'new-form'); 'done'").get()
        let encoded = try encryptLogin(["token": "cached-token", "account": "old-form"], runtime: runtime)
        try store.put(encoded, for: "userInfo_" + sourceURL, scope: sourceURL)
        XCTAssertEqual(try loginFields(runtime), ["token": "cached-token", "account": "new-form"])
    }

    func testExpiryAfterRestartDropsOnlyUnchangedMirroredFields() throws {
        var instant = Date(timeIntervalSince1970: 1000)
        let store = SourceScriptCacheStore(rootURL: rootURL, clock: { instant })
        let runtime = try makeRuntime(store)
        try writeLogin(["token": "expired-token", "account": "old-form"], runtime: runtime, lifetime: 2)
        _ = try runtime.evaluate("source.setLoginInfo('account', 'new-form'); 'done'").get()
        instant.addTimeInterval(2)
        let reopened = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL, clock: { instant }))
        XCTAssertEqual(try loginFields(reopened), ["account": "new-form"])
        XCTAssertNil(try savedVariables()["source.loginCacheMirror"])
        XCTAssertEqual(try loginFields(makeRuntime(SourceScriptCacheStore(rootURL: rootURL))), ["account": "new-form"])
    }

    func testLRUEvictionCannotRestoreOldKeychainTokenAfterRestart() throws {
        var limits = SourceScriptCacheStore.Limits()
        limits.maximumDiskEntries = 1
        var instant = Date(timeIntervalSince1970: 1000)
        let store = SourceScriptCacheStore(rootURL: rootURL, limits: limits, clock: { instant })
        let runtime = try makeRuntime(store)
        try writeLogin(["token": "evicted-token"], runtime: runtime)
        instant.addTimeInterval(1)
        try store.put("other-value", for: "other-entry", scope: sourceURL)
        let reopened = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL, limits: limits))
        XCTAssertTrue(try loginFields(reopened).isEmpty)
        XCTAssertTrue(try savedVariables().isEmpty)
        XCTAssertTrue(try loginFields(makeRuntime(SourceScriptCacheStore(rootURL: rootURL))).isEmpty)
    }

    func testSourceLogoutClearsCacheAndPersistedLogin() throws {
        let store = SourceScriptCacheStore(rootURL: rootURL)
        let runtime = try makeRuntime(store)
        try writeLogin(["token": "logout-token"], runtime: runtime)
        _ = try runtime.evaluate("source.removeLoginInfo(); 'done'").get()
        XCTAssertNil(try SourceScriptCacheStore(rootURL: rootURL).get("userInfo_" + sourceURL, scope: sourceURL))
        XCTAssertTrue(try savedVariables().isEmpty)
        XCTAssertTrue(try loginFields(makeRuntime(SourceScriptCacheStore(rootURL: rootURL))).isEmpty)
    }

    func testExplicitCacheDeleteAndNegativeLifetimeClearLogin() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        for removal in ["cache.delete('userInfo_' + source.getKey())", "cache.put('userInfo_' + source.getKey(), 'expired', -1)"] {
            try writeLogin(["token": "logout-token"], runtime: runtime)
            _ = try runtime.evaluate("source.setLoginInfo('account', 'new-form'); \(removal); 'done'").get()
            XCTAssertTrue(try loginFields(runtime).isEmpty)
            XCTAssertTrue(try savedVariables().isEmpty)
        }
    }

    func testPutLoginInfoDetachesOldCacheBeforeSavingNewForm() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        try writeLogin(["account": "cached-account"], runtime: runtime)
        XCTAssertEqual(try runtime.evaluate("source.putLoginInfo({account: 'new-form'})").get(), "true")
        XCTAssertEqual(try runtime.evaluate("cache.get('userInfo_' + source.getKey())").get(), "")
        XCTAssertEqual(try loginFields(makeRuntime(SourceScriptCacheStore(rootURL: rootURL))), ["account": "new-form"])
    }

    func testMalformedAndNonObjectCiphertextNeverReportLoginSuccess() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        _ = try runtime.evaluate("source.setLoginInfo('account', 'unchanged-form'); 'done'").get()
        for plaintext in ["[]", "null", "42", "not JSON"] {
            let encoded = try runtime.evaluate("fixtureCipher.encryptBase64(fixturePlaintext)", variables: ["fixturePlaintext": plaintext]).get()
            XCTAssertThrowsError(try runtime.evaluate("cache.put('userInfo_' + source.getKey(), fixtureCiphertext)",
                variables: ["fixtureCiphertext": encoded]).get())
        }
        XCTAssertThrowsError(try runtime.evaluate("cache.put('userInfo_' + source.getKey(), 'broken-ciphertext')").get())
        XCTAssertEqual(try savedVariables(), ["source.login.account": "unchanged-form"])
    }

    func testOversizeCiphertextDoesNotPartiallyChangeLoginState() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        try writeLogin(["token": "unchanged-token"], runtime: runtime)
        let saved = try savedVariables()
        XCTAssertThrowsError(try runtime.evaluate("cache.put('userInfo_' + source.getKey(), 'x'.repeat(262145))").get())
        XCTAssertEqual(try savedVariables(), saved)
    }

    func testExpandedMirrorCannotOverflowTheSourceVariableBudget() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        try writeLogin(["token": "unchanged-token"], runtime: runtime)
        let saved = try savedVariables()
        let fields = Dictionary(uniqueKeysWithValues: (0..<6000).map { ("field\($0)", "x") })
        let encoded = try encryptLogin(fields, runtime: runtime)
        XCTAssertLessThan(encoded.utf8.count, 256 * 1024)
        XCTAssertThrowsError(try runtime.evaluate("cache.put('userInfo_' + source.getKey(), fixtureCiphertext)",
            variables: ["fixtureCiphertext": encoded]).get())
        XCTAssertEqual(try savedVariables(), saved)
        XCTAssertEqual(try runtime.evaluate("java.getVar('source.login.token')").get(), "unchanged-token")
    }

    func testBudgetIncludesPreviouslySavedSourcePreferences() throws {
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        _ = try runtime.evaluate("source.setVariable('x'.repeat(250000)); 'done'").get()
        let saved = try savedVariables()
        let encoded = try encryptLogin(["token": String(repeating: "/", count: 8000)], runtime: runtime)
        XCTAssertThrowsError(try runtime.evaluate("cache.put('userInfo_' + source.getKey(), fixtureCiphertext)",
            variables: ["fixtureCiphertext": encoded]).get())
        XCTAssertEqual(try savedVariables(), saved)
    }

    func testMalformedMirrorFailsWithoutDiscardingTheSavedForm() throws {
        let store = SourceVariableStore(secrets: secrets)
        try store.save(["source.loginCacheMirror": #"{"fields":[]}"#, "source.login.account": "saved-form"], sourceKey: sourceURL)
        let runtime = try makeRuntime(SourceScriptCacheStore(rootURL: rootURL))
        XCTAssertThrowsError(try runtime.evaluate("source.getLoginInfo()").get())
        XCTAssertEqual(try savedVariables()["source.login.account"], "saved-form")
    }

    private func makeRuntime(_ cache: SourceScriptCacheStore) throws -> JSCoreRuntime {
        let store = SourceVariableStore(secrets: secrets)
        let key = sourceURL
        let state = RulePersistentState(initialValues: try store.restore(sourceKey: key),
            saveSourceVariables: { try store.save($0, sourceKey: key) })
        let source = BookSource(bookSourceName: "Synthetic login cache fixture", bookSourceUrl: sourceURL)
        let context = RuleExecutionContext(persistentState: state, source: source)
        let runtime = JSCoreRuntime(executionContext: context, scriptCacheStore: cache)
        _ = try runtime.evaluate("var fixtureCipher = java.createSymmetricCrypto('AES', java.androidId().getBytes().slice(0,16)); 'ready'").get()
        return runtime
    }

    private func encryptLogin(_ fields: [String: String], runtime: JSCoreRuntime) throws -> String {
        let plaintext = String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)
        return try runtime.evaluate("fixtureCipher.encryptBase64(fixturePlaintext)", variables: ["fixturePlaintext": plaintext]).get()
    }

    private func writeLogin(_ fields: [String: String], runtime: JSCoreRuntime, lifetime: Int = 0) throws {
        let encoded = try encryptLogin(fields, runtime: runtime)
        _ = try runtime.evaluate("cache.put('userInfo_' + source.getKey(), fixtureCiphertext, \(lifetime)); 'written'",
            variables: ["fixtureCiphertext": encoded]).get()
    }

    private func loginFields(_ runtime: JSCoreRuntime) throws -> [String: String] {
        let text = try runtime.evaluate("source.getLoginInfo()").get()
        return try JSONDecoder().decode([String: String].self, from: Data(text.utf8))
    }

    private func savedVariables() throws -> [String: String] {
        try SourceVariableStore(secrets: secrets).restore(sourceKey: sourceURL)
    }
}

private final class LoginCacheMemorySecrets: SecretStoring {
    private var values: [String: String] = [:]
    func set(_ value: String, for key: String) throws { values[key] = value }
    func value(for key: String) -> String? { values[key] }
    func removeValue(for key: String) throws { values.removeValue(forKey: key) }
}
