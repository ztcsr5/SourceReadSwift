import XCTest
@testable import SourceReadSwift

final class ComicContentParserTests: XCTestCase {

    func testParseImgTokensInParagraphs() {
        let chapter = BookChapter(title: "第1话", url: "https://example.com/c1", bookUrl: "https://example.com/b1", index: 0, isVip: false)
        let paragraphs = [
            "[img]https://img.example.com/page1.jpg[/img]",
            "[img]https://img.example.com/page2.png[/img]",
            "[img]https://img.example.com/page3.webp[/img]"
        ]
        let content = ChapterContent(chapter: chapter, title: "第1话", paragraphs: paragraphs, nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].id, 0)
        XCTAssertEqual(pages[0].url, "https://img.example.com/page1.jpg")
        XCTAssertEqual(pages[1].id, 1)
        XCTAssertEqual(pages[1].url, "https://img.example.com/page2.png")
        XCTAssertEqual(pages[2].id, 2)
        XCTAssertEqual(pages[2].url, "https://img.example.com/page3.webp")
    }

    func testParsePlainImageURLs() {
        let chapter = BookChapter(title: "第2话", url: "https://example.com/c2", bookUrl: "https://example.com/b1", index: 1, isVip: false)
        let paragraphs = [
            "https://img.example.com/001.jpg",
            "https://img.example.com/002.jpg"
        ]
        let content = ChapterContent(chapter: chapter, title: "第2话", paragraphs: paragraphs, nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].url, "https://img.example.com/001.jpg")
        XCTAssertEqual(pages[1].url, "https://img.example.com/002.jpg")
    }

    func testParseHTMLImgTags() {
        let chapter = BookChapter(title: "第3话", url: "https://example.com/c3", bookUrl: "https://example.com/b1", index: 2, isVip: false)
        let html = """
        <div class="comic-wrap">
            <img src="https://cdn.example.com/manga/p1.jpeg" alt="p1" />
            <img data-src="https://cdn.example.com/manga/p2.jpeg" alt="p2" />
            <img data-original="https://cdn.example.com/manga/p3.jpeg" alt="p3" />
        </div>
        """
        let content = ChapterContent(chapter: chapter, title: "第3话", paragraphs: [html], nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages[0].url, "https://cdn.example.com/manga/p1.jpeg")
        XCTAssertEqual(pages[1].url, "https://cdn.example.com/manga/p2.jpeg")
        XCTAssertEqual(pages[2].url, "https://cdn.example.com/manga/p3.jpeg")
    }

    func testParseJSONArray() {
        let chapter = BookChapter(title: "第4话", url: "https://example.com/c4", bookUrl: "https://example.com/b1", index: 3, isVip: false)
        let json = "[\"https://cdn.example.com/p1.jpg\", \"https://cdn.example.com/p2.jpg\"]"
        let content = ChapterContent(chapter: chapter, title: "第4话", paragraphs: [json], nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].url, "https://cdn.example.com/p1.jpg")
        XCTAssertEqual(pages[1].url, "https://cdn.example.com/p2.jpg")
    }

    func testDeduplication() {
        let chapter = BookChapter(title: "第5话", url: "https://example.com/c5", bookUrl: "https://example.com/b1", index: 4, isVip: false)
        let paragraphs = [
            "[img]https://img.example.com/page1.jpg[/img]",
            "[img]https://img.example.com/page1.jpg[/img]",
            "[img]https://img.example.com/page2.jpg[/img]"
        ]
        let content = ChapterContent(chapter: chapter, title: "第5话", paragraphs: paragraphs, nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].url, "https://img.example.com/page1.jpg")
        XCTAssertEqual(pages[1].url, "https://img.example.com/page2.jpg")
    }

    func testParseMarkdownImages() {
        let chapter = BookChapter(title: "第6话", url: "https://example.com/c6", bookUrl: "https://example.com/b1", index: 5, isVip: false)
        let paragraphs = [
            "![page1](https://img.example.com/md1.jpg)",
            "![page2](https://img.example.com/md2.png)"
        ]
        let content = ChapterContent(chapter: chapter, title: "第6话", paragraphs: paragraphs, nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)

        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages[0].url, "https://img.example.com/md1.jpg")
        XCTAssertEqual(pages[1].url, "https://img.example.com/md2.png")
    }

    func testNestedComicEnvelopeKeepsOrderAndPerImageHeadersWithoutMetadataImages() {
        let chapter = BookChapter(title: "第1话", url: "https://example.com/comic/1", bookUrl: "https://example.com/comic", index: 0)
        let json = #"{"cover":"/cover.png","data":{"pages":["/one.webp",{"src":"two.png","headers":{"Referer":"https://example.com/reader"}},"/one.webp","/three.png"]}}"#
        let content = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: [json], nextContentUrl: nil)
        let pages = ComicContentParser.parsePages(from: content)
        XCTAssertEqual(pages.map(\.url), ["https://example.com/one.webp", "https://example.com/comic/two.png", "https://example.com/three.png"])
        XCTAssertEqual(pages.map(\.id), [0, 1, 2])
        XCTAssertEqual(pages[1].headers["Referer"], "https://example.com/reader")
    }

    func testMixedImageSyntaxFollowsReadingOrderAndEmptyEnvelopeStaysEmpty() {
        let chapter = BookChapter(title: "第1话", url: "https://example.com/ch/1", bookUrl: "https://example.com/ch", index: 0)
        let paragraphs = [#"![one](/a.png) <img data-src='/b.png' src='/placeholder.gif'> [img]/c.png[/img]"#,
                          #"{"cover":"/cover.png","data":{"pages":[]}}"#]
        let content = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs, nextContentUrl: nil)
        XCTAssertEqual(ComicContentParser.parsePages(from: content).map(\.url),
                       ["https://example.com/a.png", "https://example.com/b.png", "https://example.com/c.png"])
    }

    func testComicCursorClampsAfterPageCountChangesAndTracksViewportNotPrefetchedRow() {
        XCTAssertEqual(ComicPagePositionPolicy.start(savedPage: 12, count: 4, startsAtEnd: false), 3)
        XCTAssertEqual(ComicPagePositionPolicy.start(savedPage: 0, count: 4, startsAtEnd: true), 3)
        XCTAssertEqual(ComicPagePositionPolicy.neighbours(of: 4, count: 6, direction: -1), [3, 2, 5])
        XCTAssertEqual(ComicPagePositionPolicy.neighbours(of: 0, count: 1, direction: 1), [])
        XCTAssertEqual(ComicPagePositionPolicy.page(at: 12, frames: [
            0: CGRect(x: 0, y: -500, width: 390, height: 400),
            1: CGRect(x: 0, y: -100, width: 390, height: 700),
            2: CGRect(x: 0, y: 600, width: 390, height: 540)
        ]), 1)
    }

    func testComicTapSidesMirrorWithoutReversingLogicalPageNumbers() {
        XCTAssertEqual(ComicPagePositionPolicy.tapStep(0.1, rtl: false), -1)
        XCTAssertEqual(ComicPagePositionPolicy.tapStep(0.9, rtl: false), 1)
        XCTAssertEqual(ComicPagePositionPolicy.tapStep(0.1, rtl: true), 1)
        XCTAssertEqual(ComicPagePositionPolicy.tapStep(0.9, rtl: true), -1)
        XCTAssertEqual(ComicPagePositionPolicy.tapStep(0.5, rtl: true), 0)
    }

    func testIncompleteChapterKeepsReadablePagesButIsNotACompleteCacheHit() {
        let chapter = BookChapter(title: "分页漫画", url: "https://example.com/comic/1",
                                  bookUrl: "https://example.com/comic", index: 0)
        let paragraphs = [#"[{"url":"/page-1.webp"},{"url":"/page-2.webp"}]"#]
        let truncated = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs,
                                       nextContentUrl: "/comic/1?p=2")
        let complete = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs, nextContentUrl: nil)
        let invalid = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["暂无漫画"], nextContentUrl: nil)

        XCTAssertEqual(ComicChapterResources(content: truncated).pages.map(\.id), [0, 1])
        XCTAssertTrue(ComicChapterResources(content: truncated).hasPendingContinuation)
        XCTAssertFalse(ComicChapterResources(content: truncated).canReuseFromCache)
        XCTAssertTrue(ComicChapterResources(content: complete).canReuseFromCache)
        XCTAssertFalse(ComicChapterResources(content: invalid).canReuseFromCache)
    }
}
