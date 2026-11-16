import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceEngineScriptHeaderTests: XCTestCase {
    func testOriginalHeaderUsesLibraryCacheAndLoginInfoOnTheWireWithExplicitOverride() async throws {
        let server = try ScriptHeaderHTTPFixture()
        defer { server.stop() }
        let source = makeSource(baseURL: server.baseURL,
            header: "@js: JSON.stringify(buildHeaders.call(this));", library: """
            var headerBase = baseUrl;
            function buildHeaders() {
              return {'X-Device':cache.get('device'), 'X-Account':source.getLoginInfoMap().get('account'),
                      'X-Library-Base':headerBase, 'X-Override':'source-value'};
            }
            """)
        let cache = SourceScriptCacheStore(isPersistent: false)
        try cache.put("synthetic-device", for: "device", scope: source.bookSourceUrl)
        let engine = makeEngine(cache: cache)
        engine.persistentState(for: source).put("synthetic-account", for: SourceLoginScript.loginInfoKey("account"))
        let books = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.map(\.name), ["Header fixture"])
        let request = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(request.headers["x-device"], "synthetic-device")
        XCTAssertEqual(request.headers["x-account"], "synthetic-account")
        XCTAssertEqual(request.headers["x-library-base"], source.cleanSourceURL)
        XCTAssertEqual(request.headers["x-override"], "url-value")
    }

    func testHeaderAjaxBootstrapCompletesOnceAndItsExplicitHeadersSurvive() async throws {
        let server = try ScriptHeaderHTTPFixture()
        defer { server.stop() }
        let source = makeSource(baseURL: server.baseURL, header: """
        @js:
        var bootstrap = java.ajax(source.bookSourceUrl + '/bootstrap,' + JSON.stringify({headers:{'X-Bootstrap':'explicit'}}));
        java.put('nonce', bootstrap.body());
        JSON.stringify({'X-Nonce':java.get('nonce')});
        """)
        let engine = makeEngine()
        let books = try await engine.searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(books.count, 1)
        let requests = server.requests
        XCTAssertEqual(requests.map(\.path), ["/bootstrap", "/search"])
        XCTAssertEqual(requests.first?.headers["x-bootstrap"], "explicit")
        XCTAssertNil(requests.first?.headers["x-nonce"])
        XCTAssertEqual(requests.last?.headers["x-nonce"], "synthetic-nonce")
        XCTAssertEqual(engine.persistentState(for: source).get("nonce"), "synthetic-nonce")
    }

    func testJavaAjaxAlsoSendsSourceScriptHeaders() async throws {
        let server = try ScriptHeaderHTTPFixture()
        defer { server.stop() }
        let source = BookSource(bookSourceName: "Ajax header fixture", bookSourceUrl: server.baseURL,
            searchUrl: "@js: java.ajax(source.bookSourceUrl + '/bootstrap'); source.bookSourceUrl + '/search';",
            ruleSearch: .init(fields: ["bookList": "$.books", "name": "$.name", "bookUrl": "$.url"]),
            header: "@js: ({'X-Script':'synthetic-value'})")
        _ = try await makeEngine().searchBooks(source: source, keyword: "fixture", page: 1).get()
        XCTAssertEqual(server.requests.map(\.path), ["/bootstrap", "/search"])
        XCTAssertEqual(server.requests.map { $0.headers["x-script"] }, ["synthetic-value", "synthetic-value"])
    }

    func testInvalidHeaderFailsBeforeSendingAnyHTTP() async throws {
        let server = try ScriptHeaderHTTPFixture()
        defer { server.stop() }
        let source = makeSource(baseURL: server.baseURL, header: "@js: throw new Error('synthetic-private-value');")
        let result = await makeEngine().searchBooks(source: source, keyword: "fixture", page: 1)
        guard case .failure(let error) = result else { return XCTFail("Invalid script header did not fail the request") }
        XCTAssertFalse(error.localizedDescription.contains("synthetic-private-value"))
        XCTAssertTrue(server.requests.isEmpty)
    }

    private func makeSource(baseURL: String, header: String, library: String = "") -> BookSource {
        BookSource(bookSourceName: "HTTP header fixture", bookSourceUrl: baseURL,
            searchUrl: baseURL + #"/search@Header:{"x-override":"url-value"}"#,
            ruleSearch: .init(fields: ["bookList": "$.books", "name": "$.name", "bookUrl": "$.url"]),
            header: header, raw: ["jsLib": library])
    }

    private func makeEngine(cache: SourceScriptCacheStore = SourceScriptCacheStore(isPersistent: false)) -> LegadoSourceEngine {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        let cookies = SourceCookieStore(storageURL: nil)
        let network = URLSessionSourceNetworkClient(session: URLSession(configuration: configuration), cookieStore: cookies)
        let engine = LegadoSourceEngine(network: network, cookieStore: cookies, scriptCacheStore: cache)
        engine.allowWebViewFallback = false
        return engine
    }
}
