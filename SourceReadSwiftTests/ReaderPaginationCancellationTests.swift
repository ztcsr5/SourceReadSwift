import Foundation
import UIKit
import XCTest
@testable import SourceReadSwift

final class ReaderPaginationCancellationTests: XCTestCase {
    func testCancelledCallerDoesNotStartDetachedPagination() async {
        let context = makeContext()
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await ReaderOffMainActorPaginator.paginateChapters([
                .init(chapterIndex: 0, title: "已离开的章节", paragraphs: ["不应再排版"], contentSignature: "old")
            ], context: context)
        }
        let pages = await operation.value
        XCTAssertTrue(pages.isEmpty)
    }

    func testCancelledTaskDoesNotReturnPartialTextOrIllustratedPages() async {
        let context = makeContext()
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let text = ReaderTextPagePaginator.paginate(chapterIndex: 0, title: "正文",
                paragraphs: ["不应再排版"], context: context)
            let illustrated = ReaderChapterPaginator.paginate(chapterIndex: 0, title: "插图",
                paragraphs: ["[img]https://example.com/page.png[/img]", "不应再排版"], context: context)
            return (text, illustrated)
        }
        let pages = await operation.value
        XCTAssertTrue(pages.0.isEmpty)
        XCTAssertTrue(pages.1.isEmpty)
    }

    func testSupersededTextWarmupDoesNotBuildOrReplaceCurrentRevision() {
        let cache = ReaderPageTextCache()
        let oldGeneration = cache.beginPrewarm(signature: "old")
        let currentGeneration = cache.beginPrewarm(signature: "current")
        var obsoleteBuilds = 0
        cache.storeIfAbsent(key: "page", signature: "old", generation: oldGeneration) {
            obsoleteBuilds += 1
            return NSAttributedString(string: "旧字号")
        }
        cache.storeIfAbsent(key: "page", signature: "current", generation: currentGeneration) {
            NSAttributedString(string: "当前字号")
        }
        XCTAssertEqual(obsoleteBuilds, 0)
        XCTAssertEqual(cache.text(key: "page", signature: "current") {
            XCTFail("The current page should already be prepared")
            return NSAttributedString(string: "unexpected")
        }.string, "当前字号")
    }

    func testRevisionChangeDuringTextBuildDropsObsoleteResult() {
        let cache = ReaderPageTextCache()
        let oldGeneration = cache.beginPrewarm(signature: "old")
        cache.storeIfAbsent(key: "page", signature: "old", generation: oldGeneration) {
            let currentGeneration = cache.beginPrewarm(signature: "current")
            cache.storeIfAbsent(key: "page", signature: "current", generation: currentGeneration) {
                NSAttributedString(string: "新页")
            }
            return NSAttributedString(string: "旧页")
        }
        XCTAssertEqual(cache.text(key: "page", signature: "current") {
            XCTFail("An obsolete completion must not evict the current result")
            return NSAttributedString(string: "unexpected")
        }.string, "新页")
    }

    func testLeavingPagedReaderCancelsWarmupWithoutDiscardingPreparedPage() {
        let cache = ReaderPageTextCache()
        _ = cache.text(key: "current", signature: "layout") { NSAttributedString(string: "当前页") }
        let generation = cache.beginPrewarm(signature: "layout")
        cache.cancelPrewarm()
        var builds = 0
        cache.storeIfAbsent(key: "next", signature: "layout", generation: generation) {
            builds += 1
            return NSAttributedString(string: "下一页")
        }
        XCTAssertEqual(builds, 0)
        XCTAssertTrue(cache.contains(key: "current", signature: "layout"))
        XCTAssertFalse(cache.contains(key: "next", signature: "layout"))
    }

    private func makeContext() -> ReaderChapterPaginationContext {
        let typography = ReaderPageTypography(font: UIFont.systemFont(ofSize: 18),
            titleFont: UIFont.boldSystemFont(ofSize: 22), lineSpacing: 6, letterSpacing: 0,
            paragraphSpacing: 10, firstLineIndent: 36, titleSpacing: 8,
            contentWidth: 348, contentHeight: 520)
        return ReaderChapterPaginationContext(typography: typography, titleTypography: typography,
            chromeLayout: .header, imageStyle: .standard, viewportHeight: 844,
            pagePadding: 21, footerHeight: 14, traditionalChinese: false)
    }
}
