import Foundation
import XCTest
@testable import SourceReadSwift

/// Covers the WebView resource-sniffing layer that `ruleContent.sourceRegex`
/// and `ruleContent.webJs` depend on. Legado uses sourceRegex to capture the
/// XHR/fetch payload an App-API source loads after the HTML shell; without this
/// layer those sources only ever see an empty shell.
@MainActor
final class WebViewResourceSniffingTests: XCTestCase {
    func testCapturedResourcesDecodesSniffedJSON() {
        let json = """
        [{"url":"https://api.example/chapter/1","body":"{\\"title\\":\\"第一章\\"}"},
         {"url":"https://api.example/chapter/2","body":"{\\"title\\":\\"第二章\\"}"}]
        """
        let resources = WebViewFallback.capturedResources(from: json)
        XCTAssertEqual(resources.count, 2)
        XCTAssertEqual(resources[0].url, "https://api.example/chapter/1")
        XCTAssertTrue(resources[1].body.contains("第二章"))
    }

    func testCapturedResourcesIgnoresMalformedJSON() {
        XCTAssertTrue(WebViewFallback.capturedResources(from: "not json").isEmpty)
        XCTAssertTrue(WebViewFallback.capturedResources(from: "{}").isEmpty)
    }

    func testFirstBodyPicksTheFirstURLMatchingSourceRegex() {
        let resources = [
            WebViewCapturedResource(url: "https://cdn.example/app.js", body: "var x = 1;"),
            WebViewCapturedResource(url: "https://api.example/book/991/chapter", body: "{\"text\":\"正文\"}"),
            WebViewCapturedResource(url: "https://api.example/book/991/chapter", body: "{\"text\":\"重复\"}")
        ]
        XCTAssertEqual(
            WebViewFallback.firstBody(in: resources, matching: "api/book/\\d+/chapter"),
            "{\"text\":\"正文\"}"
        )
    }

    func testFirstBodyReturnsNilWhenNothingMatches() {
        let resources = [WebViewCapturedResource(url: "https://cdn.example/app.js", body: "x")]
        XCTAssertNil(WebViewFallback.firstBody(in: resources, matching: "/api/"))
    }

    func testFirstBodyReturnsNilOnInvalidRegex() {
        let resources = [WebViewCapturedResource(url: "https://api.example/x", body: "x")]
        XCTAssertNil(WebViewFallback.firstBody(in: resources, matching: "("))
    }

    func testMatchesIsCaseInsensitive() {
        XCTAssertTrue(WebViewFallback.matches("https://ITUNES.apple.com/app", regex: "itunes\\.apple\\.com"))
        XCTAssertFalse(WebViewFallback.matches("https://example.com", regex: "itunes"))
    }

    // MARK: - Rule extraction

    func testRuleWebViewAssetsReadsLegadoContentFields() {
        let engine = LegadoSourceEngine()
        let source = BookSource(
            bookSourceName: "app api fixture",
            bookSourceUrl: "https://fixture.example",
            ruleContent: SourceRule(fields: [
                "content": "div#content@text",
                "webJs": "document.querySelector('#ok').innerText",
                "sourceRegex": "/api/chapter",
                "overrideUrlRegex": "itunes\\.apple\\.com"
            ])
        )

        let assets = engine.ruleWebViewAssets(source: source)
        XCTAssertEqual(assets.javaScript, "document.querySelector('#ok').innerText")
        XCTAssertEqual(assets.sourceRegex, "/api/chapter")
        XCTAssertEqual(assets.overrideUrlRegex, "itunes\\.apple\\.com")
    }

    func testRuleWebViewAssetsFallsBackToRootKeys() {
        let engine = LegadoSourceEngine()
        let source = BookSource(
            bookSourceName: "root keys fixture",
            bookSourceUrl: "https://fixture.example",
            raw: ["sourceRegex": " /api/book ", "webJs": ""]
        )

        let assets = engine.ruleWebViewAssets(source: source)
        XCTAssertEqual(assets.sourceRegex, "/api/book")
        XCTAssertNil(assets.javaScript)
        XCTAssertNil(assets.overrideUrlRegex)
    }

    func testRuleWebViewAssetsTreatsBlankValuesAsAbsent() {
        let engine = LegadoSourceEngine()
        let source = BookSource(
            bookSourceName: "blank fixture",
            bookSourceUrl: "https://fixture.example",
            ruleContent: SourceRule(fields: ["webJs": "   ", "sourceRegex": "\n"])
        )

        let assets = engine.ruleWebViewAssets(source: source)
        XCTAssertNil(assets.javaScript)
        XCTAssertNil(assets.sourceRegex)
    }
}
