import XCTest
@testable import SourceReadSwift

final class SourceVariablePersistenceTests: XCTestCase {
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
    func set(_ value: String, for key: String) throws {
        if shouldFailWrites { throw VariableWriteFailure.failed }
        values[key] = value
    }
    func value(for key: String) -> String? { values[key] ?? fallbackValue }
    func removeValue(for key: String) throws { values.removeValue(forKey: key) }
}
