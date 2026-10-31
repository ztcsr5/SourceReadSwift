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
}
