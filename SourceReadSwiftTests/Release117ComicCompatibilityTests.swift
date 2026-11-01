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

    private func content(_ paragraphs: [String], url: String = "https://comic.example.com/chapters/1") -> ChapterContent {
        .init(chapter: .init(title: "第1话", url: url, bookUrl: "https://comic.example.com/book", index: 0, isVip: false),
              title: "第1话", paragraphs: paragraphs, nextContentUrl: nil)
    }
}
