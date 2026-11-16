import Foundation
import JavaScriptCore
import XCTest
@testable import SourceReadSwift

/// Covers the WebView resource-sniffing layer that `ruleContent.sourceRegex`
/// and `ruleContent.webJs` depend on. sourceRegex returns a matched resource
/// URL; firstBody remains available for callers explicitly requesting a payload.
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
            WebViewFallback.firstBody(in: resources, matching: "book/[0-9]+/chapter"),
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

    func testSourceRegexReturnsFirstMatchingURLWithItsSignedQueryInsteadOfBody() {
        let address = "https://cdn.fixture.invalid/episode.m4a?sign=a%2Bb&part=2"
        let resources = [
            WebViewCapturedResource(url: "https://cdn.fixture.invalid/app.js", body: "unrelated"),
            WebViewCapturedResource(url: address, body: "binary response is not the playback URL"),
            WebViewCapturedResource(url: "https://cdn.fixture.invalid/later.mp3", body: "")
        ]
        XCTAssertEqual(WebViewFallback.firstURL(in: resources, matching: #".*\.(mp3|m4a).*"#), address)
        XCTAssertNil(WebViewFallback.firstURL(in: resources, matching: #"video\.mp4"#))
        XCTAssertNil(WebViewFallback.firstURL(in: resources, matching: "("))
    }

    func testSourceRegexAcceptsURLOnlyResourcesWithoutReadableBodies() {
        let address = "https://cdn.fixture.invalid/episode.mp3?token=synthetic"
        XCTAssertEqual(WebViewFallback.firstURL(in: [.init(url: address, body: "")], matching: #".*\.mp3.*"#), address)
        XCTAssertNil(WebViewFallback.firstURL(in: [.init(url: "", body: "not a URL")], matching: ".*"))
    }

    func testSourceRegexUsesWholeURLAndCaseSensitiveMatchingUnlessAuthorOptsIn() {
        let address = "https://cdn.fixture.invalid/EPISODE.MP3?sign=a%2Bb"
        let resources = [WebViewCapturedResource(url: address, body: "unused")]
        XCTAssertNil(WebViewFallback.firstURL(in: resources, matching: "MP3"))
        XCTAssertNil(WebViewFallback.firstURL(in: resources, matching: #".*\.mp3.*"#))
        XCTAssertNil(WebViewFallback.firstURL(in: resources, matching: #".*\.MP3"#))
        XCTAssertEqual(WebViewFallback.firstURL(in: resources, matching: #"(?i).*\.mp3.*"#), address)
        XCTAssertEqual(WebViewFallback.firstURL(in: resources, matching: #"https|.*\.MP3.*"#), address)
    }

    func testSourceRegexCaptureNeverReadsXHRBodyOrClonesFetchResponse() throws {
        let context = try sniffingContext(capturesBodies: false)
        context.evaluateScript("""
        var xhrBodyReads = 0;
        var xhr = new XMLHttpRequest();
        xhr.open('GET', 'https://media.fixture.invalid/large.mp3?sign=a%2Bb');
        Object.defineProperty(xhr, 'responseText', {get:function () { xhrBodyReads++; throw new Error('Must not read media'); }});
        xhr.send();
        var fetched = fetch('https://media.fixture.invalid/large.m4a');
        """)
        let resources = try snapshot(context)
        XCTAssertTrue(resources.contains { $0.url == "https://media.fixture.invalid/large.mp3?sign=a%2Bb" })
        XCTAssertTrue(resources.contains { $0.url == "https://media.fixture.invalid/final.m4a?sign=a%2Bb" })
        XCTAssertTrue(resources.allSatisfy { $0.body.isEmpty })
        XCTAssertEqual(context.evaluateScript("xhrBodyReads")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("fixtureCloneCalls")?.toInt32(), 0)
        XCTAssertEqual(context.evaluateScript("fetched === fixtureFetchResponse")?.toBool(), true)
    }

    func testSnifferCollectsCurrentMediaAndSourceElementsWithoutFetchingTheirBodies() throws {
        let context = try sniffingContext(capturesBodies: false)
        context.evaluateScript("""
        fixtureNodes = [
          {currentSrc:'https://cdn.fixture.invalid/selected.mp3?sign=a%2Bb', src:'https://cdn.fixture.invalid/fallback.mp3'},
          {currentSrc:'', src:'https://cdn.fixture.invalid/movie.m3u8?quality=high'},
          {src:'https://cdn.fixture.invalid/source.m4a?part=2'}
        ];
        """)
        let resources = try snapshot(context)
        XCTAssertEqual(resources.map(\.url), [
            "https://cdn.fixture.invalid/selected.mp3?sign=a%2Bb",
            "https://cdn.fixture.invalid/movie.m3u8?quality=high",
            "https://cdn.fixture.invalid/source.m4a?part=2"
        ])
        XCTAssertTrue(resources.allSatisfy { $0.body.isEmpty })
    }

    func testSnifferCollectsResourceTimingAndDeduplicatesRepeatedSnapshots() throws {
        let context = try sniffingContext(capturesBodies: false)
        context.evaluateScript("""
        fixtureEntries = [{name:'https://media.fixture.invalid/loaded.mp3?signature=a%2Bb'},
                          {name:'https://media.fixture.invalid/loaded.mp3?signature=a%2Bb'}];
        """)
        let first = try snapshot(context)
        XCTAssertEqual(first.map(\.url), ["https://media.fixture.invalid/loaded.mp3?signature=a%2Bb"])
        XCTAssertEqual(try snapshot(context), first)
    }

    func testSnifferRetainsBinaryXHRAddressWhenResponseTextIsNotReadable() throws {
        let context = try sniffingContext(capturesBodies: false)
        context.evaluateScript("""
        var xhr = new XMLHttpRequest();
        xhr.open('GET', 'https://media.fixture.invalid/binary.m4a?sign=a%2Bb');
        xhr.responseType = 'arraybuffer';
        xhr.send();
        """)
        let resources = try snapshot(context)
        XCTAssertEqual(resources.map(\.url), ["https://media.fixture.invalid/binary.m4a?sign=a%2Bb"])
        XCTAssertEqual(resources.first?.body, "")
    }

    func testLaterSnapshotFindsTheResourceStartedAfterWebJsReturns() throws {
        let context = try sniffingContext(capturesBodies: false)
        context.evaluateScript("""
        var webJsRuns = 0, releaseResource;
        function webJs() {
          webJsRuns++;
          releaseResource = function () {
            var xhr = new XMLHttpRequest();
            xhr.open('GET', 'https://media.fixture.invalid/delayed.mp3?sign=a%2Bb');
            xhr.responseType = 'arraybuffer';
            xhr.send();
          };
        }
        webJs();
        """)
        XCTAssertNil(WebViewFallback.firstURL(in: try snapshot(context), matching: #".*\.mp3.*"#))
        context.evaluateScript("releaseResource();")
        XCTAssertEqual(WebViewFallback.firstURL(in: try snapshot(context), matching: #".*\.mp3.*"#),
                       "https://media.fixture.invalid/delayed.mp3?sign=a%2Bb")
        XCTAssertEqual(context.evaluateScript("webJsRuns")?.toInt32(), 1)
    }

    func testSnifferKeepsCaptureBoundedAndPreservesAnExistingReadableBody() throws {
        let context = try sniffingContext()
        context.evaluateScript("""
        var xhr = new XMLHttpRequest();
        xhr.open('GET', 'https://media.fixture.invalid/retained.mp3');
        xhr.responseText = 'readable fixture body';
        xhr.send();
        fixtureNodes = [{currentSrc:'https://media.fixture.invalid/retained.mp3'}];
        """)
        XCTAssertEqual(try snapshot(context).first?.body, "readable fixture body")
        context.evaluateScript("""
        var second = new XMLHttpRequest();
        second.open('GET', 'https://media.fixture.invalid/retained.mp3');
        second.responseText = 'later response must not replace the first body';
        second.send();
        """)
        let bodies = try snapshot(context)
        XCTAssertEqual(bodies.count, 2)
        XCTAssertEqual(WebViewFallback.firstBody(in: bodies, matching: "retained"), "readable fixture body")
        let bounded = try sniffingContext(capturesBodies: false)
        bounded.evaluateScript("""
        for (var index = 0; index < 25; index++) {
          fixtureEntries.push({name:'https://media.fixture.invalid/' + index + '.mp3'});
        }
        """)
        let resources = try snapshot(bounded)
        XCTAssertEqual(resources.count, 20)
        XCTAssertEqual(resources.last?.url, "https://media.fixture.invalid/24.mp3")
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

    private func sniffingContext(capturesBodies: Bool = true) throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("""
        var window = this, fixtureNodes = [], fixtureEntries = [];
        var document = {baseURI:'https://page.fixture.invalid/watch/',
          querySelectorAll:function () { return fixtureNodes; }};
        var performance = {getEntriesByType:function () { return fixtureEntries; }};
        function XMLHttpRequest() { this.responseType = ''; this.responseText = ''; this.listeners = {}; }
        XMLHttpRequest.prototype.open = function () {};
        XMLHttpRequest.prototype.addEventListener = function (name, listener) { this.listeners[name] = listener; };
        XMLHttpRequest.prototype.send = function () { if (this.listeners.load) { this.listeners.load(); } };
        var fixtureCloneCalls = 0;
        var fixtureFetchResponse = {url:'https://media.fixture.invalid/final.m4a?sign=a%2Bb',
          clone:function () { fixtureCloneCalls++; throw new Error('Body is unreadable'); }};
        function fetch() { return {then:function (receive) { return receive(fixtureFetchResponse); }}; }
        """)
        context.evaluateScript(WebViewFallback.resourceCaptureScript(capturesBodies: capturesBodies))
        XCTAssertNil(context.exception, "The injected capture script must remain valid JavaScript")
        return context
    }

    private func snapshot(_ context: JSContext) throws -> [WebViewCapturedResource] {
        let json = try XCTUnwrap(context.evaluateScript(WebViewFallback.resourceSnapshotSource)?.toString())
        XCTAssertNil(context.exception, "Collecting browser resource URLs must not throw")
        return WebViewFallback.capturedResources(from: json)
    }
}
