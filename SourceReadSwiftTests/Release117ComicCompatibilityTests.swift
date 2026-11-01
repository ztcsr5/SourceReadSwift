import XCTest
@testable import SourceReadSwift

final class Release117ComicCompatibilityTests: XCTestCase {
    func testOriginalCorpusRecursiveImageRuleKeepsPageOrderAndReferer() throws {
        let fixture = try XCTUnwrap(TestFixtureSupport.url(name: "comic-sources-20261101", extension: "json", subdirectory: "Fixtures"))
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: fixture))
        let source = try XCTUnwrap(sources.first { $0.cleanSourceURL.contains("m.manhuatai.com") })
        let rule = try XCTUnwrap(source.ruleContent?.fields["content"])
        let payload: [String: Any] = ["data": ["current_chapter": ["chapter_img_list": [
            "https://cdn.example.com/page-1.webp", "https://cdn.example.com/page-2.webp"
        ]]]]
        let context = RuleExecutionContext()
        defer { context.cleanUp() }
        let extractor = JSONRuleExtractor(executionContext: context)
        XCTAssertEqual(extractor.stringList(from: payload, rule: "$..current_chapter.chapter_img_list.[*]").count, 2)
        let chapterURL = "https://comic.example.com/api/chapter/1"
        let html = try XCTUnwrap(extractor.string(from: payload, rule: rule, variables: ["baseUrl": chapterURL]))
        let pages = ComicContentParser.parsePages(from: content([html], url: chapterURL))
        XCTAssertEqual(pages.map(\.url), ["https://cdn.example.com/page-1.webp", "https://cdn.example.com/page-2.webp"])
        XCTAssertEqual(pages.map { $0.headers["Referer"] }, [chapterURL, chapterURL])
    }

    func testJSONObjectImagesKeepIndependentHeadersAndRelativeURLs() {
        let payload = #"[{"url":"../1.webp","headers":{"Referer":"https://comic.example/a"}},{"src":"//cdn.example.com/2.png","header":"{\"X-Token\":\"fixture\"}"},{"image":"3.jpg"}]"#
        let pages = ComicContentParser.parsePages(from: content([payload]))
        XCTAssertEqual(pages.map(\.url), ["https://comic.example.com/1.webp", "https://cdn.example.com/2.png", "https://comic.example.com/chapters/3.jpg"])
        XCTAssertEqual(pages.first?.headers["Referer"], "https://comic.example/a")
        XCTAssertEqual(pages[1].headers["X-Token"], "fixture")
        XCTAssertTrue(pages[2].headers.isEmpty)
    }

    func testMalformedImageObjectsAreNotRenderedAsHomepages() {
        XCTAssertTrue(ComicContentParser.parsePages(from: content([#"[{"url":null},{"url":42},{"name":"not a page"}]"#])).isEmpty)
    }

    func testObjectHeaderOverridesDirectiveWithoutDuplicateCasing() throws {
        let request = try XCTUnwrap(ComicImageRequest.resolve(object: [
            "url": #"https://cdn.example/1.jpg,{"headers":{"Referer":"old"}}"#,
            "headers": ["referer": "new"]
        ], base: "https://comic.example/"))
        XCTAssertEqual(request.headers, ["referer": "new"])
    }

    func testSourceGuardHomepageAndVideoPlaylistAreNotComicImages() {
        let values = ["⚠️ 检测到书源被恶意篡改", "https://ycoo.net", "https://hn.example/play/index.m3u8",
                      "[img]https://hn.example/play/index.m3u8[/img]", #"[{"url":"https://example.com/"}]"#]
        XCTAssertTrue(ComicContentParser.parsePages(from: content(values)).isEmpty)
        XCTAssertEqual(ComicContentParser.parsePages(from: content(["https://cdn.example/render?id=1", "[img]https://cdn.example/page/2[/img]"])).count, 2)
        XCTAssertTrue(ComicContentParser.parsePages(from: content([#"[img],{"headers":{"Referer":"https://example.com/"}}[/img]"#])).isEmpty)
    }

    func testBrowserVerificationIsClassifiedWithoutMistakingAnOrdinaryFooter() throws {
        let challenge = #"<!doctype html><title>MangaDex - Browser verification...</title><script src="challenge-assets/challenge.js"></script><noscript>Please enable JavaScript and cookies</noscript>"#
        XCTAssertTrue(LegadoSourceEngine.looksLikeJavaScriptChallenge(challenge))
        let diagnostic = try XCTUnwrap(SourceDiagnosticClassifier.sniffSnippet(snippet: challenge, statusCode: 200, stage: "search"))
        XCTAssertEqual(diagnostic.kind, .verification)
        XCTAssertEqual(diagnostic.status, .verificationRequired)
        XCTAssertFalse(LegadoSourceEngine.looksLikeJavaScriptChallenge("<article>教程：browser verification 是什么？</article><footer>challenge-assets/ 文档链接</footer>"))
        XCTAssertNil(SourceDiagnosticClassifier.sniffSnippet(snippet: "<article>教程：browser verification 是什么？</article><footer>challenge-assets/ 文档链接</footer>", statusCode: 200, stage: "search"))
    }

    func testOriginalNestedComicRulePreservesAuthorMetadataAndGuard() throws {
        let fixture = try XCTUnwrap(TestFixtureSupport.url(name: "comic-sources-20261101", extension: "json", subdirectory: "Fixtures"))
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: fixture))
        let source = try XCTUnwrap(sources.first { $0.cleanSourceURL.contains("kaixinman.com") })
        let marker = "//2025.10.6  夜明空\n//源社区：https://ycoo.net"
        XCTAssertTrue(source.raw["bookSourceComment"]?.contains(marker) == true, "Original source metadata must not be rewritten")
        let check = try JSCoreRuntime().evaluate(
            "String(source.bookSourceComment).includes(java.base64Decode('Ly8yMDI1LjEwLjYgIOWknOaYjuepugovL+a6kOekvuWMuu+8mmh0dHBzOi8veWNvby5uZXQ='))",
            variables: ["source": source]).get()
        XCTAssertEqual(check, "true", "The compatibility bridge must preserve, not bypass, the original guard")
        let chapter = BookChapter(title: "001", url: "https://www.kaixinman.com/chapter/1", bookUrl: "https://www.kaixinman.com/book/1", index: 0)
        let html = #"<html><body><img class="chapter-image" data-original="https://cdn.example/1.jpg"><img class="chapter-image" data-original="https://cdn.example/2.jpg"></body></html>"#
        let response = SourceResponse(url: URL(string: chapter.url)!, statusCode: 200,
            headers: ["Content-Type": "text/html"], body: html, data: Data(html.utf8))
        let parsed = try ContentParser().parse(source: source, chapter: chapter, response: response).get()
        XCTAssertEqual(ComicContentParser.parsePages(from: parsed).map(\.url), ["https://cdn.example/1.jpg", "https://cdn.example/2.jpg"],
                       "Nested java.getString must retain source and extract the original image rule")
    }

    private func content(_ paragraphs: [String], url: String = "https://comic.example.com/chapters/1") -> ChapterContent {
        .init(chapter: .init(title: "第1话", url: url, bookUrl: "https://comic.example.com/book", index: 0, isVip: false),
              title: "第1话", paragraphs: paragraphs, nextContentUrl: nil)
    }
}
