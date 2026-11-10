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

    func hasRequest(_ index: Int) -> Bool { requests[index] != nil }
    func release(_ index: Int) {
        guard let (chapter, continuation) = requests.removeValue(forKey: index) else { return }
        continuation.resume(returning: .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"])))
    }
    func finishAll() {
        isClosed = true
        for index in Array(requests.keys) { release(index) }
    }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
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
