import XCTest
@testable import SourceReadSwift

final class ReaderTocPerformanceTests: XCTestCase {
    private func chapter(_ index: Int, title: String? = nil) -> BookChapter {
        BookChapter(title: title ?? "第\(index + 1)章 内容", url: "https://test/\(index)", bookUrl: "https://test/book", index: index)
    }

    func testLongCatalogRepeatedReadsDoNotRefilter() {
        let chapters = (0..<10_000).map { chapter($0) }
        let cache = ReaderTocFilterCache()
        let start = Date()
        for _ in 0..<1_000 {
            XCTAssertEqual(cache.chapters(query: "内容", reversed: true, chapters: chapters).first?.index, 9_999)
        }
        XCTAssertEqual(cache.chapterBuildCount, 1)
        print("TOC projection 10000 chapters / 1000 reads / builds=\(cache.chapterBuildCount) / seconds=\(Date().timeIntervalSince(start))")
    }

    func testMiddleChapterRefreshInvalidatesSameSizeCatalog() {
        var chapters = (0..<5).map { chapter($0) }
        let cache = ReaderTocFilterCache()
        XCTAssertTrue(cache.chapters(query: "修订", reversed: false, chapters: chapters).isEmpty)
        chapters[2] = chapter(2, title: "修订后的标题")
        XCTAssertEqual(cache.chapters(query: "修订", reversed: false, chapters: chapters).map(\.index), [2])
        XCTAssertEqual(cache.chapterBuildCount, 2)
    }

    func testReverseAndSearchKeepSourceChapterIdentity() {
        let chapters = (0..<200).map { chapter($0) }
        let cache = ReaderTocFilterCache()
        let visible = cache.chapters(query: "173", reversed: true, chapters: chapters)
        XCTAssertEqual(visible.map(\.index), [172])
        XCTAssertEqual(visible.first?.id, chapters[172].id)
        XCTAssertEqual(cache.chapters(query: "", reversed: true, chapters: chapters).last?.index, 0)
    }

    func testEmptyCatalogInvalidatesPreviousNonemptyResult() {
        // Empty input must also remain a valid memoized result.
        let cache = ReaderTocFilterCache()
        XCTAssertTrue(cache.chapters(query: "", reversed: false, chapters: []).isEmpty)
        let first = cache.chapters(query: "", reversed: false, chapters: [chapter(1)])
        XCTAssertEqual(first.count, 1)
        XCTAssertTrue(cache.chapters(query: "", reversed: false, chapters: []).isEmpty)
    }

    func testRepeatedSortTogglesReuseBothProjections() {
        let chapters = (0..<10_000).map { chapter($0) }
        let cache = ReaderTocFilterCache()
        let start = Date()
        for index in 0..<1_000 {
            let reversed = index % 2 == 0
            let rows = cache.chapters(query: "内容", reversed: reversed, chapters: chapters)
            XCTAssertEqual(rows.first?.index, reversed ? 9_999 : 0)
        }
        XCTAssertEqual(cache.chapterBuildCount, 1, "Toggling sort must not refilter 10,000 chapters every time")
        print("TOC 10000 chapters / 1000 alternating sorts / builds=\(cache.chapterBuildCount) / seconds=\(Date().timeIntervalSince(start))")
    }

    func testReverseProjectionInvalidatesWhenMiddleChapterChanges() {
        var chapters = (0..<5).map { chapter($0) }
        let cache = ReaderTocFilterCache()
        _ = cache.chapters(query: "", reversed: true, chapters: chapters)
        chapters[2] = chapter(2, title: "修订")
        let reversed = cache.chapters(query: "", reversed: true, chapters: chapters)
        XCTAssertEqual(reversed[2].title, "修订")
        XCTAssertEqual(cache.chapters(query: "", reversed: false, chapters: chapters)[2].title, "修订")
    }

    func testSortIntentGoesToFirstVisibleRowNotCurrentChapter() {
        let chapters = (0..<1000).map { chapter($0) }
        let reverse = Array(chapters.reversed())
        XCTAssertEqual(ReaderTocScrollIntent.firstRow.target(in: reverse, preferred: 0, fallback: 0), chapters[999].id)
        XCTAssertEqual(ReaderTocScrollIntent.firstRow.target(in: chapters, preferred: 800, fallback: 800), chapters[0].id)
        XCTAssertEqual(ReaderTocScrollIntent.currentChapter.target(in: reverse, preferred: 0, fallback: 0), chapters[0].id)
    }

    func testSearchScrollTargetCannotReferToFilteredOutChapter() {
        let chapters = [chapter(400), chapter(600)]
        XCTAssertEqual(ReaderTocScrollIntent.firstRow.target(in: chapters, preferred: 0, fallback: 0), chapters[0].id)
        XCTAssertNil(ReaderTocScrollIntent.firstRow.target(in: [], preferred: 0, fallback: 0))
    }

    func testPresentationSlotsDoNotMoveWhenTenThousandChaptersReverse() {
        let chapters = (0..<10_000).map { chapter($0) }
        let reverse = Array(chapters.reversed())
        XCTAssertEqual(Array(chapters.indices), Array(reverse.indices))
        XCTAssertEqual(ReaderTocScrollIntent.firstRow.row(in: reverse, preferred: 0, fallback: 0), 0)
        XCTAssertEqual(ReaderTocScrollIntent.currentChapter.row(in: reverse, preferred: 173, fallback: 0), 9_826)
        // Reusing the row must not accidentally select the old chapter.
        XCTAssertEqual(reverse[0].index, 9_999)
        XCTAssertEqual(chapters[0].index, 0)
        XCTAssertNil(ReaderTocScrollIntent.currentChapter.row(in: [], preferred: 0, fallback: 0))
    }
}
