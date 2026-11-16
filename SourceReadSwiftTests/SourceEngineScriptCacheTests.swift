import Foundation
import XCTest
@testable import SourceReadSwift

/// Exercises cache continuity through production login and search entry points.
final class SourceEngineScriptCacheTests: XCTestCase {
    func testLoginRegistrationReachesSearchAndSurvivesEngineRecreation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if FileManager.default.fileExists(atPath: root.path) { try? FileManager.default.removeItem(at: root) }
        }
        let source = makeSource()
        let network = CacheRegistrationNetwork()
        let first = makeEngine(network: network, root: root)
        let registration = try await first.login(source: source, credentials: ["account": "synthetic-account"]).get()
        XCTAssertEqual(registration.status, .passed)
        let books = try await first.searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.map(\.name), ["Authenticated fixture"])

        let restarted = makeEngine(network: network, root: root)
        let verification = try await restarted.verifyLogin(source: source).get()
        XCTAssertEqual(verification.status, .passed)
        _ = try await restarted.searchBooks(source: source, keyword: "fixture", page: 1).get()
        let registrations = await network.registrations
        XCTAssertEqual(registrations, ["device-fixture", "device-fixture"])
    }

    func testIndependentOriginalRecordsDoNotShareCacheThroughSourceURL() async throws {
        let firstRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let secondRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if FileManager.default.fileExists(atPath: firstRoot.path) { try? FileManager.default.removeItem(at: firstRoot) }
            if FileManager.default.fileExists(atPath: secondRoot.path) { try? FileManager.default.removeItem(at: secondRoot) }
        }
        let source = makeSource()
        let network = CacheRegistrationNetwork()
        let first = makeEngine(network: network, root: firstRoot)
        let registration = try await first.login(source: source, credentials: ["account": "synthetic-account"]).get()
        XCTAssertEqual(registration.status, .passed)
        let other = makeEngine(network: network, root: secondRoot)
        let verification = try await other.verifyLogin(source: source).get()
        XCTAssertNotEqual(verification.status, .passed)
        let attempted = await other.searchBooks(source: source, keyword: "fixture", page: 1)
        if case .success = attempted { XCTFail("An unrelated record must not inherit the preceding record's registration") }
    }

    private func makeSource() -> BookSource {
        BookSource(bookSourceName: "Cache registration fixture", bookSourceUrl: "https://cache-engine.fixture.invalid",
            searchUrl: "@js:source.bookSourceUrl + '/search?device=' + cache.get('device')",
            ruleSearch: .init(fields: ["bookList": "$.books", "name": "$.name", "bookUrl": "$.url"]),
            loginUrl: "cache.put('device', 'device-fixture');",
            loginCheckJs: "cache.get('device') === 'device-fixture' ? 'true' : 'false'")
    }

    private func makeEngine(network: CacheRegistrationNetwork, root: URL) -> LegadoSourceEngine {
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(rootURL: root))
        engine.allowWebViewFallback = false
        return engine
    }
}

private actor CacheRegistrationNetwork: SourceNetworkClient {
    private(set) var registrations: [String] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let registration = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "device" })?.value ?? ""
        registrations.append(registration)
        guard registration == "device-fixture" else { return .failure(.network("Fixture registration is absent")) }
        let body = #"{"books":[{"name":"Authenticated fixture","url":"/book"}]}"#
        return .success(SourceResponse(url: request.url, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8)))
    }
}
