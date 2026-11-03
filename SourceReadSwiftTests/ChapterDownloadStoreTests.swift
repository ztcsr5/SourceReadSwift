import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterDownloadStoreTests: XCTestCase {
    func testDownloadRecordPersistsProgressAndResumesAsPaused() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ChapterDownloadPersistence(fileManager: .default, rootURL: root)
        let store = ChapterDownloadStore(persistence: persistence)
        store.begin(bookID: "book", sourceURL: "source", bookURL: "book-url", title: "Book", chapterCount: 3)
        store.markRunning(bookID: "book")
        store.markCompleted(bookID: "book", chapterIndex: 1)

        let reloaded = ChapterDownloadStore(persistence: persistence)
        let record = try XCTUnwrap(reloaded.record(bookID: "book"))
        XCTAssertEqual(record.status, .paused)
        XCTAssertEqual(record.completedIndexes, [1])
        XCTAssertEqual(record.progress, 1.0 / 3.0, accuracy: 0.001)
        try? FileManager.default.removeItem(at: root)
    }

    func testFailedChapterIsRetriedAndClearedOnSuccess() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ChapterDownloadPersistence(fileManager: .default, rootURL: root)
        let store = ChapterDownloadStore(persistence: persistence)
        store.begin(bookID: "book", sourceURL: "source", bookURL: "book-url", title: "Book", chapterCount: 1)
        store.markFailed(bookID: "book", chapterIndex: 0, message: "timeout")
        store.markCompleted(bookID: "book", chapterIndex: 0)
        store.finish(bookID: "book")
        let record = try XCTUnwrap(store.record(bookID: "book"))
        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.failedIndexes, [])
        XCTAssertEqual(record.completedIndexes, [0])
        try? FileManager.default.removeItem(at: root)
    }

    func testCancelledJobCannotPauseOrRemoveReplacementAfterLateResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root))
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let coordinator = ChapterDownloadCoordinator(store: store)
        let engine = HeldChapterDownloadEngine()
        let source = BookSource(bookSourceName: "Offline fixture", bookSourceUrl: "https://fixture.local")
        let first = downloadChapter(0)
        let replacement = downloadChapter(1)

        coordinator.start(bookID: "book", source: source, title: "Book", chapters: [first],
            engine: engine, cacheStore: cache, purifyRules: [])
        try await waitForDownload(0, engine: engine)
        let old = try XCTUnwrap(coordinator.cancel(bookID: "book"))
        XCTAssertEqual(store.record(bookID: "book")?.status, .cancelled)
        coordinator.start(bookID: "book", source: source, title: "Book", chapters: [replacement],
            engine: engine, cacheStore: cache, purifyRules: [])
        try await waitForDownload(1, engine: engine)

        await engine.release(first)
        await old.value
        XCTAssertTrue(coordinator.isRunning(bookID: "book"))
        XCTAssertEqual(store.record(bookID: "book")?.status, .running)
        XCTAssertFalse(cache.isCached(sourceURL: source.bookSourceUrl, chapter: first, purifyRules: []))
        let current = coordinator.cancel(bookID: "book")
        await engine.release(replacement)
        await current?.value
    }

    func testDownloadRechecksActualCacheInsteadOfTrustingOldCompletedIndexes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root))
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let coordinator = ChapterDownloadCoordinator(store: store)
        let engine = HeldChapterDownloadEngine()
        let source = BookSource(bookSourceName: "Offline fixture", bookSourceUrl: "https://fixture.local")
        let cleared = downloadChapter(0)
        let retained = downloadChapter(1)
        store.begin(bookID: "book", sourceURL: source.bookSourceUrl, bookURL: cleared.bookUrl,
            title: "Book", chapterCount: 2)
        store.markCompleted(bookID: "book", chapterIndex: 0)
        cache.save(ChapterContent(chapter: retained, title: retained.title, paragraphs: ["已缓存正文"]),
            sourceURL: source.bookSourceUrl, purifyRules: [])
        coordinator.start(bookID: "book", source: source, title: "Book", chapters: [cleared, retained],
            engine: engine, cacheStore: cache, purifyRules: [])
        XCTAssertEqual(store.record(bookID: "book")?.completedIndexes, [1])
        try await waitForDownload(0, engine: engine)
        let current = coordinator.cancel(bookID: "book")
        await engine.release(cleared)
        await current?.value
    }

    private func downloadChapter(_ index: Int) -> BookChapter {
        BookChapter(title: "Chapter \(index)", url: "https://fixture.local/read/\(index)",
            bookUrl: "https://fixture.local/book", index: index, isVip: false)
    }

    private func waitForDownload(_ index: Int, engine: HeldChapterDownloadEngine) async throws {
        for _ in 0..<200 {
            if await engine.hasRequest(index) { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw DownloadFixtureFailure.chapterWasNotRequested(index)
    }

    func testCancelledDownloadKeepsRecordForExplicitResume() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let persistence = ChapterDownloadPersistence(fileManager: .default, rootURL: root)
        let store = ChapterDownloadStore(persistence: persistence)
        store.begin(bookID: "book", sourceURL: "source", bookURL: "book-url", title: "Book", chapterCount: 2)
        store.markCompleted(bookID: "book", chapterIndex: 0)
        store.markCancelled(bookID: "book")
        XCTAssertEqual(store.record(bookID: "book")?.status, .cancelled)
        XCTAssertEqual(store.record(bookID: "book")?.completedIndexes, [0])
        try? FileManager.default.removeItem(at: root)
    }
}

private enum DownloadFixtureFailure: Error {
    case chapterWasNotRequested(Int)
}

private actor HeldChapterDownloadEngine: SourceEngine {
    private var requests: [Int: CheckedContinuation<Result<ChapterContent, SourceEngineError>, Never>] = [:]

    func hasRequest(_ index: Int) -> Bool { requests[index] != nil }
    func release(_ chapter: BookChapter) {
        requests.removeValue(forKey: chapter.index)?.resume(
            returning: .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"])))
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        await withCheckedContinuation { requests[chapter.index] = $0 }
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Not used by cache fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}
