import XCTest
import Combine
@testable import SourceReadSwift

@MainActor
final class ChapterDownloadBlockingTests: XCTestCase {
    func testTextSourceBlockPausesWithoutRequestingRemainingChaptersAndCanResume() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterDownloadPersistence(rootURL: root)
        let store = ChapterDownloadStore(persistence: persistence)
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let coordinator = ChapterDownloadCoordinator(store: store)
        let source = BookSource(bookSourceName: "Blocked fixture", bookSourceUrl: "https://blocked.invalid")
        let chapters = (0..<6).map { chapter($0) }
        let initialWindow = expectation(description: "All three controlled chapter requests are awaiting results")
        let engine = ControlledBlockedDownloadEngine(initialWindowStarted: { initialWindow.fulfill() })
        let notice = "访问过快，请在1分钟后重试"
        cache.save(ChapterContent(chapter: chapters[0], title: chapters[0].title, paragraphs: ["已保存正文"]),
            sourceURL: source.bookSourceUrl, purifyRules: [], retainOffline: true)
        try await cache.flush()

        coordinator.start(bookID: "book", source: source, title: "Book", chapters: chapters,
            engine: engine, cacheStore: cache, purifyRules: [])
        // Preparing the durable cache is separate from the source-block response deadline.
        await fulfillment(of: [initialWindow], timeout: 10)
        let initialWindowStarted = await engine.hasPending([1, 2, 3])
        XCTAssertTrue(initialWindowStarted)
        guard initialWindowStarted else {
            let cancelled = coordinator.cancel(bookID: "book")
            await engine.finishAll()
            await cancelled?.value
            return
        }
        let released = await engine.release(1, result: .failure(.blocked(notice)))
        XCTAssertTrue(released, "The block response must reach an already waiting request")
        let paused = await waitForStop(coordinator)
        if !paused {
            let cancelled = coordinator.cancel(bookID: "book")
            await engine.finishAll()
            await cancelled?.value
        }
        await engine.finishAll()
        XCTAssertTrue(paused, "A source block must stop the queue instead of retrying or filling another slot")
        XCTAssertEqual(store.record(bookID: "book")?.status, .paused)
        XCTAssertEqual(store.record(bookID: "book")?.completedIndexes, [0])
        XCTAssertEqual(store.record(bookID: "book")?.failedIndexes, [1])
        XCTAssertEqual(store.record(bookID: "book")?.lastError, SourceEngineError.blocked(notice).displayMessage)
        let requested = await engine.requestedIndexes
        XCTAssertEqual(Set(requested), [1, 2, 3])
        XCTAssertEqual(requested.filter { $0 == 1 }.count, 1)
        let reopened = ChapterDownloadStore(persistence: persistence).record(bookID: "book")
        XCTAssertEqual(reopened?.status, .paused)
        XCTAssertEqual(reopened?.completedIndexes, [0])
        XCTAssertEqual(reopened?.failedIndexes, [1], "Cancelled and unrequested chapters are not failed chapters")

        let resumedEngine = ImmediateBlockedDownloadEngine()
        coordinator.start(bookID: "book", source: source, title: "Book", chapters: chapters,
            engine: resumedEngine, cacheStore: cache, purifyRules: [])
        let resumed = await waitForStop(coordinator)
        XCTAssertTrue(resumed)
        XCTAssertEqual(store.record(bookID: "book")?.status, .completed)
        XCTAssertEqual(store.record(bookID: "book")?.completedIndexes, Array(0..<6))
        XCTAssertEqual(store.record(bookID: "book")?.failedIndexes, [])
        let resumedRequests = await resumedEngine.requestedIndexes
        XCTAssertFalse(resumedRequests.contains(0), "Explicit resume reuses durable progress")
    }

    func testOrdinaryEmptyAndNotFoundChaptersDoNotPauseTheWholeBook() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root))
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let coordinator = ChapterDownloadCoordinator(store: store)
        let engine = ImmediateBlockedDownloadEngine(failures: [0: .empty("正文为空"), 1: .network("HTTP 404")])
        let source = BookSource(bookSourceName: "Missing chapter fixture", bookSourceUrl: "https://blocked.invalid")
        let progressFinished = expectation(description: "Both failed chapters and all three durable successes are recorded")
        let subscription = store.$records.filter { records in
            records["book"]?.failedIndexes == [0, 1] && records["book"]?.completedIndexes == [2, 3, 4]
        }.prefix(1).sink { _ in progressFinished.fulfill() }
        defer { subscription.cancel() }
        coordinator.start(bookID: "book", source: source, title: "Book", chapters: (0..<5).map { chapter($0) },
            engine: engine, cacheStore: cache, purifyRules: [])
        // Keep the real 0.8 + 1.6 second retries, allowing the remaining budget for disk acknowledgements and CI scheduling.
        await fulfillment(of: [progressFinished], timeout: 15)
        let finished = await waitForStop(coordinator)
        if !finished { await coordinator.cancel(bookID: "book")?.value }
        XCTAssertTrue(finished)
        XCTAssertFalse(coordinator.isRunning(bookID: "book"))
        XCTAssertEqual(store.record(bookID: "book")?.status, .failed)
        XCTAssertEqual(store.record(bookID: "book")?.failedIndexes, [0, 1])
        XCTAssertEqual(store.record(bookID: "book")?.completedIndexes, [2, 3, 4])
        let requested = await engine.requestedIndexes
        let requestCounts = Dictionary(grouping: requested, by: { $0 }).mapValues { $0.count }
        XCTAssertEqual(requestCounts, [0: ChapterFetchPolicy.maximumAttempts, 1: ChapterFetchPolicy.maximumAttempts,
                                       2: 1, 3: 1, 4: 1])
    }

    func testComicSourceBlockPreservesSavedImagesAndCanResume() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root))
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let archive = ComicOfflineArchive(directory: root.appendingPathComponent("comics"))
        let png = comicPNG
        let coordinator = ChapterDownloadCoordinator(store: store, comicArchive: archive, fetchComicPage: { _ in .success(png) })
        let source = BookSource(bookSourceName: "Comic block fixture", bookSourceUrl: "https://blocked.invalid", bookSourceType: 2)
        let chapters = (0..<3).map { chapter($0) }
        let engine = ImmediateBlockedDownloadEngine(failures: [1: .sourceUpdateRequired])
        coordinator.start(bookID: "book", source: source, title: "Comic", chapters: chapters,
            engine: engine, cacheStore: cache, purifyRules: [])
        let stopped = await waitForStop(coordinator)
        XCTAssertTrue(stopped)
        XCTAssertEqual(store.record(bookID: "book")?.status, .paused)
        XCTAssertEqual(store.record(bookID: "book")?.completedIndexes, [0])
        XCTAssertEqual(store.record(bookID: "book")?.failedIndexes, [1])
        let firstRequests = await engine.requestedIndexes
        XCTAssertEqual(firstRequests, [0, 1])
        let firstSaved = await archive.contains(sourceURL: source.bookSourceUrl, chapter: chapters[0])
        XCTAssertTrue(firstSaved)

        let resumedEngine = ImmediateBlockedDownloadEngine()
        coordinator.start(bookID: "book", source: source, title: "Comic", chapters: chapters,
            engine: resumedEngine, cacheStore: cache, purifyRules: [])
        let resumed = await waitForStop(coordinator)
        XCTAssertTrue(resumed)
        XCTAssertEqual(store.record(bookID: "book")?.status, .completed)
        XCTAssertEqual(store.record(bookID: "book")?.completedIndexes, [0, 1, 2])
        let resumedRequests = await resumedEngine.requestedIndexes
        XCTAssertEqual(resumedRequests, [1, 2])
    }

    func testComicImageRateLimitPausesButImageNotFoundContinues() async {
        for status in [429, 404] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root))
            let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
            let archive = ComicOfflineArchive(directory: root.appendingPathComponent("comics"))
            let coordinator = ChapterDownloadCoordinator(store: store, comicArchive: archive,
                fetchComicPage: { _ in .failure(.http(status)) })
            let source = BookSource(bookSourceName: "Image fixture", bookSourceUrl: "https://blocked.invalid", bookSourceType: 2)
            let engine = ImmediateBlockedDownloadEngine()
            coordinator.start(bookID: "book", source: source, title: "Comic", chapters: (0..<3).map { chapter($0) },
                engine: engine, cacheStore: cache, purifyRules: [])
            let stopped = await waitForStop(coordinator)
            XCTAssertTrue(stopped)
            let requested = await engine.requestedIndexes
            XCTAssertEqual(requested, status == 429 ? [0] : [0, 1, 2])
            XCTAssertEqual(store.record(bookID: "book")?.status, status == 429 ? .paused : .failed)
            XCTAssertEqual(store.record(bookID: "book")?.failedIndexes, status == 429 ? [0] : [0, 1, 2])
        }
    }

    private var comicPNG: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII=")!
    }

    private func chapter(_ index: Int) -> BookChapter {
        BookChapter(title: "Chapter \(index)", url: "https://blocked.invalid/read/\(index)",
            bookUrl: "https://blocked.invalid/book", index: index)
    }

    private func waitForStop(_ coordinator: ChapterDownloadCoordinator, attempts: Int = 300) async -> Bool {
        for _ in 0..<attempts {
            if !coordinator.isRunning(bookID: "book") { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    }
}

private actor ControlledBlockedDownloadEngine: SourceEngine {
    private var pending: [Int: CheckedContinuation<Result<ChapterContent, SourceEngineError>, Never>] = [:]
    private var isClosed = false
    private let initialWindowStarted: @Sendable () -> Void
    private(set) var requestedIndexes: [Int] = []

    init(initialWindowStarted: @escaping @Sendable () -> Void) {
        self.initialWindowStarted = initialWindowStarted
    }

    func hasPending(_ indexes: Set<Int>) -> Bool { indexes.isSubset(of: Set(pending.keys)) }

    @discardableResult
    func release(_ index: Int, result: Result<ChapterContent, SourceEngineError>) -> Bool {
        guard let continuation = pending.removeValue(forKey: index) else { return false }
        continuation.resume(returning: result)
        return true
    }

    func finishAll() {
        isClosed = true
        for index in Array(pending.keys) { release(index, result: .failure(.network("Fixture cancelled"))) }
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        requestedIndexes.append(chapter.index)
        guard !isClosed else { return .failure(.network("Fixture cancelled")) }
        return await withCheckedContinuation {
            pending[chapter.index] = $0
            if Set(pending.keys) == [1, 2, 3] { initialWindowStarted() }
        }
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Unused fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}

private actor ImmediateBlockedDownloadEngine: SourceEngine {
    private let failures: [Int: SourceEngineError]
    private(set) var requestedIndexes: [Int] = []

    init(failures: [Int: SourceEngineError] = [:]) { self.failures = failures }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        requestedIndexes.append(chapter.index)
        if let failure = failures[chapter.index] { return .failure(failure) }
        let paragraph = source.sourceKind == .comic ? "https://cdn.invalid/page.png" : "正文"
        return .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: [paragraph]))
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Unused fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}
