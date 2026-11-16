import XCTest
@testable import SourceReadSwift

final class ComicChapterWindowTests: XCTestCase {
    func testSplicingRetainsOrderAndTheWindowIsBoundedDuringForwardAndReverseReading() {
        var window = ComicStripChapterWindow()
        window.reset(to: chapter(2))
        XCTAssertTrue(window.stitch(chapter(1), around: 2))
        XCTAssertTrue(window.stitch(chapter(3), around: 2))
        XCTAssertEqual(window.chapters.map(\.offset), [1, 2, 3])
        XCTAssertEqual(window.snapshot.indices[.init(chapterOffset: 2, pageIndex: 1)], 3)
        XCTAssertFalse(window.stitch(chapter(3), around: 2), "Do not mount a duplicate chapter from a late response")
        XCTAssertFalse(window.stitch(chapter(5), around: 3), "Do not skip a missing neighbour")

        XCTAssertTrue(window.stitch(chapter(4), around: 3))
        XCTAssertEqual(window.chapters.map(\.offset), [2, 3, 4])
        XCTAssertTrue(window.stitch(chapter(1), around: 2))
        XCTAssertEqual(window.chapters.map(\.offset), [1, 2, 3])
        XCTAssertTrue(window.prune(around: 2, includesNeighbours: false))
        XCTAssertEqual(window.chapters.map(\.offset), [2])
    }

    func testIncompleteChapterBlocksContinuationInBothDirections() {
        var window = ComicStripChapterWindow()
        window.reset(to: chapter(0, partial: true))
        XCTAssertFalse(window.stitch(chapter(1), around: 0))
        window.reset(to: chapter(1))
        XCTAssertFalse(window.stitch(chapter(0, partial: true), around: 1))
        XCTAssertFalse(window.stitch(chapter(2, partial: true), around: 1))
        XCTAssertEqual(window.chapters.map(\.offset), [1])
    }

    func testSpeculativePageRequestsAreDirectionalAndBounded() {
        XCTAssertEqual(ComicPagePositionPolicy.prefetchOrder(around: 5, count: 20, direction: -1, depth: 2), [4, 3, 6])
        XCTAssertEqual(ComicPagePositionPolicy.prefetchOrder(around: 0, count: 3, direction: 1, depth: 500), [1, 2])
        XCTAssertEqual(ComicPagePositionPolicy.prefetchOrder(around: 0, count: 3, direction: 1, depth: 0), [])
    }

    private func chapter(_ index: Int, partial: Bool = false) -> ComicStripChapter {
        let chapter = BookChapter(title: "Fixture", url: "https://comic.example/chapter/\(index)",
                                  bookUrl: "https://comic.example/book", index: index)
        let paragraphs = (1...2).map { "[img]https://comic.example/\(index)/\($0).png[/img]" }
        let content = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs,
                                     nextContentUrl: partial ? "https://comic.example/next" : nil)
        let resources = ComicChapterResources(content: content)
        return ComicStripChapter(offset: index, resources: resources,
            requests: resources.pages.map { ComicImageRequest(url: $0.url, headers: $0.headers) })
    }
}
