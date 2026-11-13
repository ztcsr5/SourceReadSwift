import XCTest
import WebKit
@testable import SourceReadSwift

/// Synthetic prose with structural contracts from the supplied source rules;
/// these are not live-site coverage claims or copied novel chapters.
final class WebsiteSourceFamilyInferenceTests: XCTestCase {
    private let prose = String(repeating: "山谷的风从纸页间穿过，故事继续向前。\n", count: 12)

    func testOfficialAndThirdPartyHTMLFamiliesUseProductionValidation() throws {
        // Supplied source corpus: Qidian mobile .content, SF #ChapterBody,
        // third-party Biquge .readcontent, and standard article templates.
        let families = [
            ("qidian-mobile", "<ul class='y-list'><li class='y-list__item'><a href='/chapter/1'><h2>第一章 起风</h2></a></li><li class='y-list__item'><a href='/chapter/2'><h2>第二章 山谷</h2></a></li></ul>", "<div class='content'>", "</div>"),
            ("sf-catalog", "<div class='story-catalog'><div class='catalog-list'><ul><li><a href='/chapter/1'>第一章 起风</a></li><li><a href='/chapter/2'>第二章 山谷</a></li></ul></div></div>", "<div id='ChapterBody'>", "</div>"),
            ("biquge-dl", "<dl id='list-chapterAll'><dd><a href='/chapter/1'>第一章 起风</a></dd><dd><a href='/chapter/2'>第二章 山谷</a></dd></dl>", "<div class='readcontent'>", "</div>"),
            ("article-template", "<section id='chapters'><a href='/chapter/1'>第一章 起风</a><a href='/chapter/2'>第二章 山谷</a></section>", "<article class='entry-content'>", "</article>")
        ]
        for (family, links, opening, closing) in families {
            let catalog = sample("/book/1", "<h1>结构样本</h1>" + links)
            let chapter = sample("/chapter/2", "<h1>第二章 山谷</h1>" + opening + "<p>" + prose + "</p>" + closing)
            let draft = try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: family)
            XCTAssertEqual(draft.chapterCount, 2, family)
            XCTAssertTrue(draft.preview.joined().contains("山谷的风"), family)
            XCTAssertNil(draft.source.searchUrl, family)
            XCTAssertEqual(ExploreCategoryParser.parse(exploreUrl: draft.source.exploreUrl).count, 1, family)
        }
    }

    func testDirectJSONWrappersGenerateOnlyObservedAPIFields() throws {
        for wrapper in ["root", "data", "result"] {
            let entries: [[String: Any]] = [["title": "第一章", "url": "https://family.example/chapter/1"],
                                          ["title": "第二章", "url": "https://family.example/chapter/2"]]
            let catalogObject: [String: Any] = wrapper == "root" ? ["chapters": entries, "bookName": "接口样本", "token": "PRIVATE-SAMPLE"] :
                [wrapper: ["chapters": entries, "bookName": "接口样本"], "token": "PRIVATE-SAMPLE"]
            let chapterObject: [String: Any] = wrapper == "root" ? ["content": prose] : [wrapper: ["content": prose]]
            let catalog = try jsonSample("/api/catalog/1", catalogObject)
            let chapter = try jsonSample("/chapter/2", chapterObject)
            let draft = try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: "JSON")
            XCTAssertEqual(draft.chapterCount, 2, wrapper)
            XCTAssertEqual(draft.contentSelector, wrapper == "root" ? "$.content" : "$.\(wrapper).content")
            XCTAssertTrue(draft.preview.joined().contains("山谷的风"))
            XCTAssertNil(draft.source.searchUrl)
            XCTAssertNil(draft.source.exploreUrl, "A catalog response does not reveal a discovery/search API")
            let exported = String(decoding: try JSONEncoder().encode(draft.source), as: UTF8.self)
            XCTAssertFalse(exported.contains("PRIVATE-SAMPLE"))
            XCTAssertFalse(exported.contains("山谷的风"), "Sample chapter text must not enter the exported source")
            let detail = try BookDetailParser().parse(source: draft.source, book: draft.example,
                                                      response: WebsiteSourceInference.response(catalog)).get()
            XCTAssertEqual(detail.tocUrl, catalog.url.absoluteString)
            let edited = try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: "JSON",
                                                         tocCSS: draft.tocSelector, contentCSS: draft.contentSelector)
            XCTAssertEqual(edited.chapterCount, 2)
        }
    }

    func testAmbiguousAndUnsafeJSONCannotBecomePretendSources() throws {
        let chapter = try jsonSample("/chapter/2", ["content": prose])
        for target in ["https://foreign.example/chapter/1", "https://family.example/chapter/1?token=private", "javascript:alert(1)", "1"] {
            let catalog = try jsonSample("/api/catalog", ["chapters": [["name": "第一章", "url": target],
                                                                      ["name": "第二章", "url": chapter.url.absoluteString]]])
            XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: catalog, chapter: chapter, name: "x"), target)
        }
        let rows = [["name": "第一章", "url": "https://family.example/chapter/1"],
                    ["name": "第二章", "url": chapter.url.absoluteString]]
        let ambiguous = try jsonSample("/api/catalog", ["chapters": rows, "list": rows])
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: ambiguous, chapter: chapter, name: "x"))
        let selected = try WebsiteSourceInference.infer(catalog: ambiguous, chapter: chapter, name: "x", tocCSS: "$.chapters[*]")
        XCTAssertEqual(selected.chapterCount, 2)
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: ambiguous, chapter: chapter, name: "x", tocCSS: "@js:java.ajax('https://foreign.example/')"))
        let locked = try jsonSample("/chapter/2", ["needLogin": true, "content": ""])
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: ambiguous, chapter: locked, name: "x", tocCSS: "$.chapters[*]"))
        let missing = try jsonSample("/api/catalog", ["chapters": [["id": 1, "title": "第一章"], ["id": 2, "title": "第二章"]]])
        XCTAssertThrowsError(try WebsiteSourceInference.infer(catalog: missing, chapter: chapter, name: "x"), "No URL may be invented from numeric IDs")
    }

    @MainActor func testActualWebKitCaptureSeparatesDirectJSONFromRenderedHTML() async throws {
        let json = #"{"data":{"content":"direct-json"},"token":"memory-only"}"#
        let pages = ["<pre>" + json + "</pre>",
                     "<h1>渲染章节</h1><article>可见正文</article><form><input value='PRIVATE-FORM'></form><script>var marker='PRIVATE-SCRIPT';</script>"]
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previousWindow = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        let container = UIViewController()
        window.rootViewController = container
        window.makeKeyAndVisible()
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 568))
        container.view.addSubview(web)
        defer { web.stopLoading(); web.navigationDelegate = nil; window.isHidden = true; previousWindow?.makeKeyAndVisible() }
        // A hosted CI WebContent process has taken 18–44 seconds to cold-start.
        // Separate that fixture readiness from the unchanged 8-second capture waits.
        let warmed = expectation(description: "WebKit fixture process ready")
        let bootstrap = WebsiteSampleNavigation(loaded: warmed)
        web.navigationDelegate = bootstrap
        web.loadHTMLString("<!doctype html><html><body>fixture ready</body></html>", baseURL: nil)
        await fulfillment(of: [warmed], timeout: 60)
        for (index, html) in pages.enumerated() {
            let loaded = expectation(description: "local page \(index)")
            let observer = WebsiteSampleNavigation(loaded: loaded)
            web.navigationDelegate = observer
            web.loadHTMLString(html, baseURL: nil)
            // A second navigation in the same hosted WebContent process has
            // still taken >8 s on a cold CI runner; the assertion is the
            // captured content, not how fast WebKit acknowledges the commit.
            await fulfillment(of: [loaded], timeout: 30)
            let capturedValue = try await web.evaluateJavaScript(WebsitePageCapture.script)
            let captured = try XCTUnwrap(capturedValue as? String)
            if index == 0 {
                XCTAssertTrue(ResponseFormatDetector.looksLikeJSON(captured))
                XCTAssertFalse(captured.contains("<pre>"))
            } else {
                XCTAssertTrue(captured.contains("可见正文"))
                XCTAssertFalse(captured.contains("PRIVATE-FORM"))
                XCTAssertFalse(captured.contains("PRIVATE-SCRIPT"))
                XCTAssertFalse(ResponseFormatDetector.looksLikeJSON(captured))
            }
            web.navigationDelegate = nil
            web.stopLoading()
        }
    }

    private func sample(_ path: String, _ body: String) -> WebsitePageSample {
        .init(url: URL(string: "https://family.example" + path)!, html: body)
    }

    private func jsonSample(_ path: String, _ object: [String: Any]) throws -> WebsitePageSample {
        sample(path, String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self))
    }
}

@MainActor private final class WebsiteSampleNavigation: NSObject, WKNavigationDelegate {
    let loaded: XCTestExpectation
    init(loaded: XCTestExpectation) { self.loaded = loaded; super.init() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded.fulfill() }
}
