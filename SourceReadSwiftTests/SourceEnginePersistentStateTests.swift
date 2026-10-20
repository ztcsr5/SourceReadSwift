import Foundation
import XCTest
@testable import SourceReadSwift

/// Per-source state is where `loginInfo`, cookies and cached tokens live.
/// These tests pin the two isolation boundaries that used to collapse:
/// URL-less drafts sharing one bucket, and the 101st source wiping every bucket.
final class SourceEnginePersistentStateTests: XCTestCase {
    func testSameURLWithDifferentCasingAndWhitespaceSharesState() {
        let first = source(name: "A", url: "  HTTPS://Example.COM/Book  ")
        let second = source(name: "B", url: "https://example.com/book")
        XCTAssertEqual(
            LegadoSourceEngine.persistentStateKey(for: first),
            LegadoSourceEngine.persistentStateKey(for: second)
        )
    }

    func testURLLessSourcesWithDifferentRulesDoNotShareLoginState() {
        let first = source(
            name: "Draft",
            url: "",
            raw: ["ruleSearch": #"{"bookList":"$.a"}"#]
        )
        let second = source(
            name: "Draft",
            url: "",
            raw: ["ruleSearch": #"{"bookList":"$.b"}"#]
        )
        XCTAssertNotEqual(
            LegadoSourceEngine.persistentStateKey(for: first),
            LegadoSourceEngine.persistentStateKey(for: second)
        )

        let engine = LegadoSourceEngine(network: NoopNetworkClient())
        engine.persistentState(for: first).put("KEY-1", for: "loginInfo.token")
        XCTAssertEqual(engine.persistentState(for: second).get("loginInfo.token"), "")
        XCTAssertEqual(engine.persistentState(for: first).get("loginInfo.token"), "KEY-1")
    }

    func testStateEvictionIsLeastRecentlyUsedInsteadOfRemoveAll() {
        let engine = LegadoSourceEngine(network: NoopNetworkClient())
        var sources: [BookSource] = []
        for index in 0..<LegadoSourceEngine.maximumPersistentStates {
            let item = source(name: "Source \(index)", url: "https://example.com/\(index)")
            sources.append(item)
            engine.persistentState(for: item).put("value-\(index)", for: "loginInfo.token")
        }

        // Refresh source 0 so source 1 becomes the oldest entry.
        XCTAssertEqual(engine.persistentState(for: sources[0]).get("loginInfo.token"), "value-0")

        let overflow = source(name: "Overflow", url: "https://example.com/overflow")
        engine.persistentState(for: overflow).put("overflow", for: "loginInfo.token")

        XCTAssertEqual(engine.persistentState(for: sources[0]).get("loginInfo.token"), "value-0")
        XCTAssertEqual(engine.persistentState(for: sources[2]).get("loginInfo.token"), "value-2")
        XCTAssertEqual(engine.persistentState(for: sources[1]).get("loginInfo.token"), "")
    }

    private func source(name: String, url: String, raw: [String: String] = [:]) -> BookSource {
        BookSource(
            bookSourceName: name,
            bookSourceUrl: url,
            searchUrl: "https://example.com/search?q={{key}}",
            raw: raw
        )
    }
}

private final class NoopNetworkClient: SourceNetworkClient, @unchecked Sendable {
    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        .failure(.network("NoopNetworkClient does not perform requests"))
    }
}