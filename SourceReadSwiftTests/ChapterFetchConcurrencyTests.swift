import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterFetchConcurrencyTests: XCTestCase {
    func testExportReusesAFreeRequestSlotWhileEarlierChaptersAreStillPending() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let engine = HeldExportEngine()
        let source = BookSource(bookSourceName: "并发夹具", bookSourceUrl: "https://concurrency.invalid")
        let chapters = (0..<5).map {
            BookChapter(title: "第\($0)章", url: "https://concurrency.invalid/\($0)", bookUrl: "book", index: $0)
        }
        let export = Task { @MainActor in
            await BookExportChapterLoader.load(chapters: chapters, cachedChapters: [], source: source,
                engine: engine, cacheStore: cache, purifyRules: [], progress: { _, _ in })
        }
        let initialWindow = await waitForRequest(2, engine: engine)
        XCTAssertTrue(initialWindow)
        let fourthStartedEarly = await engine.hasRequest(3)
        XCTAssertFalse(fourthStartedEarly, "No more than three network requests may be active")
        await engine.release(2)
        let reusedSlot = await waitForRequest(3, engine: engine)
        XCTAssertTrue(reusedSlot, "The third completed request must not wait for the first two slow chapters")
        let firstStillPending = await engine.hasRequest(0)
        XCTAssertTrue(firstStillPending)
        export.cancel()
        await engine.finishAll()
        _ = await export.value
        let peak = await engine.peakRequests
        XCTAssertLessThanOrEqual(peak, ChapterFetchPolicy.concurrentRequestLimit)
    }

    func testExportStopsAtSourceBlockAndReportsTheOriginalFailureWithoutLosingCachedChapters() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let engine = HeldExportEngine()
        let source = BookSource(bookSourceName: "Blocked export fixture", bookSourceUrl: "https://concurrency.invalid")
        let chapters = (0..<6).map {
            BookChapter(title: "第\($0)章", url: "https://concurrency.invalid/\($0)", bookUrl: "book", index: $0)
        }
        let cached = ChapterContent(chapter: chapters[0], title: chapters[0].title, paragraphs: ["已有正文"])
        cache.save(cached, sourceURL: source.bookSourceUrl, purifyRules: [])
        let failure = SourceEngineError.blocked("访问过快，请在1分钟后重试")
        var reportedFailure: SourceEngineError?
        let stopped = expectation(description: "blocked export returned without requesting the rest")
        let export = Task { @MainActor in
            let retained = await BookExportChapterLoader.load(chapters: chapters, cachedChapters: [cached], source: source,
                engine: engine, cacheStore: cache, purifyRules: [], progress: { _, _ in },
                onSourceFailure: { reportedFailure = $0 })
            stopped.fulfill()
            return retained
        }
        let initialWindow = await waitForRequest(3, engine: engine)
        XCTAssertTrue(initialWindow)
        await engine.release(1, result: .failure(failure))
        await fulfillment(of: [stopped], timeout: 2)
        export.cancel()
        await engine.finishAll()
        let retained = await export.value
        XCTAssertEqual(retained, [cached])
        XCTAssertEqual(reportedFailure, failure)
        let requested = await engine.requestedIndexes
        XCTAssertEqual(Set(requested), [1, 2, 3])
        XCTAssertEqual(requested.filter { $0 == 1 }.count, 1)
        XCTAssertEqual(cache.content(sourceURL: source.bookSourceUrl, chapter: chapters[0], purifyRules: [])?.paragraphs, ["已有正文"])
    }

    private func waitForRequest(_ index: Int, engine: HeldExportEngine) async -> Bool {
        for _ in 0..<200 {
            if await engine.hasRequest(index) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}

private actor HeldExportEngine: SourceEngine {
    private var requests: [Int: (BookChapter, CheckedContinuation<Result<ChapterContent, SourceEngineError>, Never>)] = [:]
    private var isClosed = false
    private(set) var peakRequests = 0
    private(set) var requestedIndexes: [Int] = []

    func hasRequest(_ index: Int) -> Bool { requests[index] != nil }
    func release(_ index: Int, result: Result<ChapterContent, SourceEngineError>? = nil) {
        guard let (chapter, continuation) = requests.removeValue(forKey: index) else { return }
        continuation.resume(returning: result ?? .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"])))
    }
    func finishAll() {
        isClosed = true
        for index in Array(requests.keys) { release(index) }
    }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        requestedIndexes.append(chapter.index)
        guard !isClosed else { return .failure(.unsupported("Fixture closed")) }
        return await withCheckedContinuation { continuation in
            requests[chapter.index] = (chapter, continuation)
            peakRequests = max(peakRequests, requests.count)
        }
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Unused concurrency fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}
