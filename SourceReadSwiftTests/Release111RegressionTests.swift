import XCTest
import SwiftUI
@testable import SourceReadSwift

final class Release111RegressionTests: XCTestCase {
    func testResultPagesAlwaysLimitTwentyRows() {
        let input = Array(0..<47)
        XCTAssertEqual(ResultPage.slice(input, page: 0), Array(0..<20))
        XCTAssertEqual(ResultPage.slice(input, page: 1), Array(20..<40))
        XCTAssertEqual(ResultPage.slice(input, page: 2), Array(40..<47))
        XCTAssertEqual(ResultPage.slice(input, page: 999), Array(40..<47))
        XCTAssertEqual(ResultPage.slice([Int](), page: 0), [])
        XCTAssertEqual(ResultPage.slice(input, page: -2), Array(0..<20))
    }

    @MainActor func testDiscoverGroupingPaginatesBothDisplayModes() {
        let model = DiscoverViewModel()
        model.results = (0..<47).map {
            SearchBook(name: "Book\($0)", author: "Author", coverUrl: nil, bookUrl: "https://fixture.test/\($0)", sourceName: "Fixture", sourceUrl: "https://fixture.test")
        }
        XCTAssertEqual(model.resultPageCount, 3)
        model.resultPage = 1
        XCTAssertEqual(model.pagedAggregatedResults.count, 20)
        model.displayMode = .bySource
        XCTAssertEqual(model.resultPage, 0)
        model.resultPage = 2
        XCTAssertEqual(model.pagedGroupedResults.flatMap(\.books).count, 7)
    }

    func testChapterAlignmentHandlesChineseNumberAndFrontMatterOffset() {
        let chapters = [chapter("前言", 0), chapter("第74章 火龙走水", 1), chapter("第七十五章 新篇", 2)]
        XCTAssertEqual(SourceChapterAlignment.match(title: "第七十四章 火龙走水", index: 73, in: chapters)?.index, 1)
        XCTAssertEqual(SourceChapterAlignment.match(title: "第75章　新篇", index: 74, in: chapters)?.index, 2)
        XCTAssertEqual(SourceChapterAlignment.number("第一千零二十四章 起"), 1024)
        XCTAssertEqual(SourceChapterAlignment.number("第１２８章 起"), 128)
        XCTAssertNil(SourceChapterAlignment.match(title: nil, index: 0, in: []))
    }

    func testChapterAlignmentPreservesExactSplitChapterAndSafeFallback() {
        let chapters = [chapter("第十章 上", 0), chapter("第十章 下", 1), chapter("后记", 2)]
        XCTAssertEqual(SourceChapterAlignment.match(title: "第10章 下", index: 0, in: chapters)?.index, 1)
        XCTAssertEqual(SourceChapterAlignment.match(title: "不同章节", index: 100, in: chapters)?.index, 2)
    }

    func testJSONListAcceptsOrderModifiersBeforeJSONAndJS() {
        let extractor = JSONRuleExtractor()
        let root: [String:Any] = ["comic_chapter": [["id":1], ["id":2], ["id":3]]]
        XCTAssertEqual(extractor.list(from: root, rule: "-$..comic_chapter[*]").compactMap { $0["id"] as? Int }, [3,2,1])
        XCTAssertEqual(extractor.list(from: "html", rule: "+@js:[{id:1},{id:2}]").compactMap { $0["id"] as? Int }, [1,2])
        XCTAssertEqual(extractor.list(from: "html", rule: "-@js:[{id:1},{id:2}]").compactMap { $0["id"] as? Int }, [2,1])
    }

    @MainActor func testTexturesAreSeparateFromSolidColourAndCached() {
        XCTAssertFalse(ReaderBackground.kraft.hasTexture)
        XCTAssertTrue(ReaderBackground.kraftTexture.hasTexture)
        let a = ReaderPaperTexture.image(background: .kraftTexture, night: false)
        XCTAssertTrue(a === ReaderPaperTexture.image(background: .kraftTexture, night: false))
        XCTAssertNotEqual(a.pngData(), ReaderPaperTexture.image(background: .linen, night: false).pngData())
    }

    @MainActor func testDiagnosticPolicyDoesNotPermanentlyDisableProductionFallback() async {
        let engine = LegadoSourceEngine()
        XCTAssertTrue(engine.allowWebViewFallback)
        await SourceRequestContext.$isDiagnostic.withValue(true) {
            XCTAssertFalse(engine.allowWebViewFallback)
        }
        XCTAssertTrue(engine.allowWebViewFallback)
    }

    func testDiagnosticSchedulerRefillsSlotBeforeSlowPeerCompletes() async {
        let engine = SchedulingProbeEngine()
        let sources = (0..<4).map { BookSource(bookSourceName: String($0), bookSourceUrl: "https://fixture\($0).test", searchUrl: "/search") }
        let result = await SourceBatchDiagnosticRunner(engine: engine).run(sources: sources, keyword: "test", deepCheck: false, timeout: 2, batchSize: 2)
        let events = await engine.events
        XCTAssertEqual(result.reports.count, 4)
        XCTAssertLessThan(events.firstIndex(of: "start2")!, events.firstIndex(of: "finish0")!)
        let observed = await engine.observedDiagnosticPolicy
        XCTAssertTrue(observed.allSatisfy { $0 })
        XCTAssertFalse(SourceRequestContext.isDiagnostic)
    }

    @MainActor func testCoverTapUsesAnimationBeforeCursorCommit() async {
        let host = CoverPageHostController()
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let committed = expectation(description: "animated turn commits")
        var changes: [Int] = []
        host.apply(pageIdentity: "page1", contentRevision: "rev1", previousIdentity: "page0", currentIdentity: "page1", nextIdentity: "page2",
            hasPrevious: true, hasNext: true, previous: AnyView(Text("0")), current: AnyView(Text("1")), next: AnyView(Text("2")),
            onCommit: { direction in changes.append(direction); committed.fulfill() }, onInteractionChange: { _ in }, onPageContainerLayout: nil)
        let request = ReaderPageTurnRequest(direction: 1)
        host.requestTurn(request)
        host.requestTurn(request)
        XCTAssertTrue(changes.isEmpty)
        await fulfillment(of: [committed], timeout: 2)
        XCTAssertEqual(changes, [1])
        host.cancelInteraction()
    }

    private func chapter(_ title: String, _ index: Int) -> BookChapter {
        BookChapter(title: title, url: "https://fixture.test/\(index)", bookUrl: "https://fixture.test/book", index: index)
    }
}

private actor SchedulingProbeEngine: SourceEngine {
    var events: [String] = []
    var observedDiagnosticPolicy: [Bool] = []
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        let id = source.bookSourceName
        events.append("start" + id)
        observedDiagnosticPolicy.append(SourceRequestContext.isDiagnostic)
        try? await Task.sleep(nanoseconds: id == "0" ? 300_000_000 : 5_000_000)
        events.append("finish" + id)
        return .success([])
    }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.empty("fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> { .failure(.empty("fixture")) }
}
