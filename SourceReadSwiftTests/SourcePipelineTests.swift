import Foundation
import XCTest
@testable import SourceReadSwift

final class SourcePipelineTests: XCTestCase {
    func testPipelineRunsAllFourStagesAndBuildsReport() async throws {
        let source = fixtureSource()
        let searchBook = SearchBook(
            name: "Pipeline Book", author: "Author", coverUrl: nil,
            bookUrl: "https://fixture.example/book/1",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil
        )
        let detail = BookDetail(
            name: searchBook.name, author: searchBook.author, coverUrl: nil,
            bookUrl: searchBook.bookUrl, tocUrl: "https://fixture.example/toc/1",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl,
            intro: "Intro", latestChapter: "Chapter 1"
        )
        let chapter = BookChapter(title: "Chapter 1", url: "https://fixture.example/chapter/1", bookUrl: detail.bookUrl, index: 0, isVip: false)
        let content = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"], nextContentUrl: nil)
        let engine = PipelineStubEngine(search: .success([searchBook]), detail: .success(detail), toc: .success([chapter]), content: .success(content))

        let execution = await engine.runPipelineReport(source: source, keyword: "swift", timeout: 1)

        XCTAssertTrue(execution.isSuccess)
        XCTAssertNil(execution.error)
        XCTAssertTrue(execution.result.isComplete)
        XCTAssertEqual(execution.result.steps.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertEqual(execution.result.steps.map(\.matchCount), [1, 1, 1, 1])
        XCTAssertTrue(execution.result.steps.allSatisfy { ($0.elapsedMilliseconds ?? -1) >= 0 })
        XCTAssertEqual(execution.result.report.overallStatus, .passed)
    }

    func testEmptySearchRetainsWarningStepAndError() async {
        let engine = PipelineStubEngine(search: .success([]), detail: nil, toc: nil, content: nil)
        let execution = await engine.runPipelineReport(source: fixtureSource(), keyword: "missing", timeout: 1)

        guard case .empty(let message)? = execution.error else {
            return XCTFail("expected empty search error, got \(String(describing: execution.error))")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(execution.result.steps.map(\.stage), [.search])
        XCTAssertEqual(execution.result.steps.first?.status, .warning)
        XCTAssertEqual(execution.result.report.overallStatus, .warning)
    }

    func testDetailFailureRetainsSearchAndFailedStage() async {
        let searchBook = SearchBook(name: "Book", author: nil, coverUrl: nil, bookUrl: "https://fixture.example/book/1", sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil)
        let engine = PipelineStubEngine(
            search: .success([searchBook]),
            detail: .failure(.network("detail offline")),
            toc: nil,
            content: nil
        )

        let execution = await engine.runPipelineReport(source: fixtureSource(), keyword: "book", timeout: 1)

        XCTAssertEqual(execution.result.steps.map(\.stage), [.search, .detail])
        XCTAssertEqual(execution.result.searchBooks.count, 1)
        XCTAssertEqual(execution.result.steps.last?.failureClassification, "network(\"detail offline\")")
        XCTAssertFalse(execution.isSuccess)
        XCTAssertEqual(execution.error, .network("detail offline"))
    }

    func testContentFailureIncludesAllStageObservations() async {
        let chapter = BookChapter(title: "One", url: "https://fixture.example/chapter/1", bookUrl: "https://fixture.example/book/1", index: 0, isVip: false)
        let detail = BookDetail(name: "Book", author: nil, coverUrl: nil, bookUrl: chapter.bookUrl, tocUrl: nil, sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil, latestChapter: nil)
        let searchBook = SearchBook(name: "Book", author: nil, coverUrl: nil, bookUrl: detail.bookUrl, sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil)
        let engine = PipelineStubEngine(
            search: .success([searchBook]),
            detail: .success(detail),
            toc: .success([chapter]),
            content: .failure(.rule("content selector did not match"))
        )

        let execution = await engine.runPipelineReport(source: fixtureSource(), keyword: "book", timeout: 1)

        XCTAssertEqual(execution.result.steps.map(\.stage), [.search, .detail, .toc, .content])
        XCTAssertEqual(execution.result.steps.last?.status, .failed)
        XCTAssertEqual(execution.result.chapters.count, 1)
        XCTAssertEqual(execution.result.report.firstFailure?.stage, .content)
    }

    func testEmptyContentIsFailureInsteadOfFalseSuccess() async {
        let chapter = BookChapter(title: "One", url: "https://fixture.example/chapter/1", bookUrl: "https://fixture.example/book/1", index: 0, isVip: false)
        let detail = BookDetail(name: "Book", author: nil, coverUrl: nil, bookUrl: chapter.bookUrl, tocUrl: nil, sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil, latestChapter: nil)
        let searchBook = SearchBook(name: "Book", author: nil, coverUrl: nil, bookUrl: detail.bookUrl, sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil)
        let empty = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["", "  \n"], nextContentUrl: nil)
        let engine = PipelineStubEngine(search: .success([searchBook]), detail: .success(detail), toc: .success([chapter]), content: .success(empty))

        let execution = await engine.runPipelineReport(source: fixtureSource(), keyword: "book", timeout: 1)

        XCTAssertFalse(execution.isSuccess)
        XCTAssertEqual(execution.error, .empty("正文为空"))
        XCTAssertFalse(execution.result.isComplete)
        XCTAssertEqual(execution.result.steps.last?.status, .failed)
    }

    func testPipelineTimeoutIsClassifiedAsNetworkAndKeepsSearchStep() async {
        let engine = PipelineStubEngine(
            search: .success([]), detail: nil, toc: nil, content: nil,
            searchDelayNanoseconds: 150_000_000
        )
        let execution = await engine.runPipelineReport(source: fixtureSource(), keyword: "slow", timeout: 0.01)

        guard case .network(let message)? = execution.error else {
            return XCTFail("expected timeout network error, got \(String(describing: execution.error))")
        }
        XCTAssertTrue(message.contains("超时"))
        XCTAssertEqual(execution.result.steps.count, 1)
        XCTAssertEqual(execution.result.steps[0].stage, .search)
    }

    func testCompatibilityWrapperReturnsResultOnly() async {
        let engine = PipelineStubEngine(search: .success([]), detail: nil, toc: nil, content: nil)
        let result = await engine.runPipeline(source: fixtureSource(), keyword: "missing", timeout: 1)
        guard case .failure(.empty(_)) = result else {
            return XCTFail("expected empty result, got \(result)")
        }
    }

    func testPipelineRetainsFullChapterListAndUsesProductionPageLimits() async {
        let detail = BookDetail(name: "Book", author: nil, coverUrl: nil, bookUrl: "https://fixture.example/book/1", tocUrl: "https://fixture.example/toc/1", sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil, latestChapter: nil)
        let searchBook = SearchBook(name: "Book", author: nil, coverUrl: nil, bookUrl: detail.bookUrl, sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil)
        let chapters = (0..<25).map { index in
            BookChapter(title: "Chapter \(index)", url: "https://fixture.example/chapter/\(index)", bookUrl: detail.bookUrl, index: index, isVip: false)
        }
        let firstChapter = chapters[0]
        let content = ChapterContent(chapter: firstChapter, title: firstChapter.title, paragraphs: ["正文"], nextContentUrl: nil)
        let engine = PipelineRecordingEngine(search: [searchBook], detail: detail, chapters: chapters, content: content)

        let execution = await engine.runPipelineReport(source: fixtureSource(), keyword: "book", timeout: 1)

        XCTAssertTrue(execution.isSuccess)
        XCTAssertEqual(execution.result.chapters.count, 25)
        XCTAssertEqual(execution.result.chapters.last?.index, 24)
        XCTAssertEqual(engine.recordedTOCMaxPages, 30)
        XCTAssertEqual(engine.recordedContentMaxPages, 8)
    }

    func testPipelineForwardsExplicitPageLimits() async {
        let detail = BookDetail(name: "Book", author: nil, coverUrl: nil, bookUrl: "https://fixture.example/book/1", tocUrl: nil, sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil, latestChapter: nil)
        let searchBook = SearchBook(name: "Book", author: nil, coverUrl: nil, bookUrl: detail.bookUrl, sourceName: "Fixture", sourceUrl: "https://fixture.example", intro: nil)
        let chapter = BookChapter(title: "One", url: "https://fixture.example/chapter/1", bookUrl: detail.bookUrl, index: 0, isVip: false)
        let content = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"], nextContentUrl: nil)
        let engine = PipelineRecordingEngine(search: [searchBook], detail: detail, chapters: [chapter], content: content)

        _ = await engine.runPipelineReport(
            source: fixtureSource(),
            keyword: "book",
            timeout: 1,
            tocMaxPages: 3,
            contentMaxPages: 2
        )

        XCTAssertEqual(engine.recordedTOCMaxPages, 3)
        XCTAssertEqual(engine.recordedContentMaxPages, 2)
    }
    private func fixtureSource() -> BookSource {
        BookSource(bookSourceName: "Fixture", bookSourceUrl: "https://fixture.example")
    }
}

private struct PipelineStubEngine: SourceEngine {
    let search: Result<[SearchBook], SourceEngineError>
    let detail: Result<BookDetail, SourceEngineError>?
    let toc: Result<[BookChapter], SourceEngineError>?
    let content: Result<ChapterContent, SourceEngineError>?
    let searchDelayNanoseconds: UInt64

    init(
        search: Result<[SearchBook], SourceEngineError>,
        detail: Result<BookDetail, SourceEngineError>?,
        toc: Result<[BookChapter], SourceEngineError>?,
        content: Result<ChapterContent, SourceEngineError>?,
        searchDelayNanoseconds: UInt64 = 0
    ) {
        self.search = search
        self.detail = detail
        self.toc = toc
        self.content = content
        self.searchDelayNanoseconds = searchDelayNanoseconds
    }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        if searchDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: searchDelayNanoseconds)
        }
        return search
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        detail ?? .failure(.empty("detail fixture missing"))
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        toc ?? .failure(.empty("toc fixture missing"))
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        content ?? .failure(.empty("content fixture missing"))
    }

    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .success(SourceLoginVerification(status: .notConfigured, message: "fixture", cookiePresent: false))
    }
}

/// Records the page limits that reach the engine so the pipeline contract can
/// be asserted without a live network. Reference semantics are required here.
private final class PipelineRecordingEngine: SourceEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var tocMaxPages: Int?
    private var contentMaxPages: Int?

    private let search: [SearchBook]
    private let detail: BookDetail
    private let chapters: [BookChapter]
    private let content: ChapterContent

    init(search: [SearchBook], detail: BookDetail, chapters: [BookChapter], content: ChapterContent) {
        self.search = search
        self.detail = detail
        self.chapters = chapters
        self.content = content
    }

    var recordedTOCMaxPages: Int? {
        lock.lock(); defer { lock.unlock() }
        return tocMaxPages
    }

    var recordedContentMaxPages: Int? {
        lock.lock(); defer { lock.unlock() }
        return contentMaxPages
    }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        .success(search)
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        .success(detail)
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        .success(chapters)
    }

    func getChapterList(source: BookSource, book: BookDetail, maxPages: Int) async -> Result<[BookChapter], SourceEngineError> {
        lock.lock(); tocMaxPages = maxPages; lock.unlock()
        return .success(chapters)
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        .success(content)
    }

    func getContent(source: BookSource, chapter: BookChapter, maxPages: Int) async -> Result<ChapterContent, SourceEngineError> {
        lock.lock(); contentMaxPages = maxPages; lock.unlock()
        return .success(content)
    }

    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .success(SourceLoginVerification(status: .notConfigured, message: "fixture", cookiePresent: false))
    }
}