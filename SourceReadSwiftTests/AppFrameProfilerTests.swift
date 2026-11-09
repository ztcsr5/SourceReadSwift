import XCTest
import Combine
@testable import SourceReadSwift

final class AppFrameProfilerTests: XCTestCase {
    func testAdaptiveRefreshTransitionDoesNotCountIdleIntervalAsElevenMissedFrames() {
        var cadence = AppFrameCadence()
        var histogram = AppFrameHistogram()
        XCTAssertNil(cadence.sample(timestamp: 1, scheduledSeconds: 0.1))
        if let sample = cadence.sample(timestamp: 1.1, scheduledSeconds: 1 / 120.0) {
            histogram.record(seconds: sample.elapsed, scheduledSeconds: sample.scheduled)
        }
        XCTAssertEqual(histogram.samples, 1)
        XCTAssertEqual(histogram.missedScheduledFrames, 0)
        if let sample = cadence.sample(timestamp: 1.2, scheduledSeconds: 1 / 120.0) {
            histogram.record(seconds: sample.elapsed, scheduledSeconds: sample.scheduled)
        }
        XCTAssertEqual(histogram.missedScheduledFrames, 11,
                       "A real 100ms stall after both callbacks request 120Hz must remain visible")
    }

    func test120CadenceAndSystem60CadenceAreNotConflated() {
        var h = AppFrameHistogram()
        for _ in 0..<120 { h.record(seconds: 1 / 120.0, scheduledSeconds: 1 / 120.0) }
        XCTAssertEqual(h.averageFPS, 120, accuracy: 0.01)
        XCTAssertEqual(h.over120Budget, 0)
        XCTAssertEqual(h.missedScheduledFrames, 0)
        h.record(seconds: 1 / 60.0, scheduledSeconds: 1 / 60.0)
        XCTAssertEqual(h.over120Budget, 1)
        XCTAssertEqual(h.missedScheduledFrames, 0, "Adaptive 60Hz is not a missed system deadline")
    }

    func testLongStallPercentilesAreNotClampedToHalfASecond() {
        var h = AppFrameHistogram()
        h.record(seconds: 1.25, scheduledSeconds: 1 / 120.0)
        XCTAssertEqual(h.percentileMilliseconds(0.99), 1250)
        XCTAssertEqual(h.missedScheduledFrames, 149)
        XCTAssertEqual(h.worstSeconds, 1.25)
    }

    func testInvalidIntervalsAreDiscarded() {
        var h = AppFrameHistogram()
        for v in [Double.nan, .infinity, -1, 0, 6] { h.record(seconds: v, scheduledSeconds: 1 / 120.0) }
        h.record(seconds: 1, scheduledSeconds: 0)
        XCTAssertEqual(h.samples, 0)
        XCTAssertEqual(h.percentileMilliseconds(.nan), 0)
        XCTAssertEqual(h.averageFPS, 0)
    }

    @MainActor func testDiagnosticAndSearchProgressDoNotInvalidateWholeApp() {
        let app = AppState()
        var notifications = 0
        let subscription = app.objectWillChange.sink { notifications += 1 }
        for i in 0..<250 { app.record(DiagnosticEvent(level: .info, stage: "fixture", message: "\(i)")) }
        app.discoverViewModel.objectWillChange.send()
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(app.diagnostics.count, 200)
        app.isTabChromeHidden.toggle()
        XCTAssertEqual(notifications, 1, "Real navigation state must still publish")
        withExtendedLifetime(subscription) {}
    }

    @MainActor func testChapterCacheMutationsDoNotInvalidateWholeApp() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let cache = ChapterContentCacheStore(persistence: persistence)
        let app = AppState(chapterContentCacheStore: cache)
        func drainMainQueue() async {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        await drainMainQueue()
        var appNotifications = 0
        var cacheNotifications = 0
        let appChanges = app.objectWillChange.sink { appNotifications += 1 }
        // `entries` is deliberately not @Published: the offline list is the
        // only subscriber, and the LRU touch in markRead must stay silent.
        let cacheChanges = cache.objectWillChange.sink { cacheNotifications += 1 }

        let chapter = BookChapter(title: "下一章", url: "chapter-1", bookUrl: "book", index: 1)
        let content = ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"], nextContentUrl: nil)
        cache.save(content, sourceURL: "source", purifyRules: [])
        XCTAssertEqual(cache.entries.count, 1, "The offline list must still see saved chapters")
        XCTAssertEqual(cacheNotifications, 1)
        cache.markRead(sourceURL: "source", chapter: chapter, purifyRules: [])
        XCTAssertEqual(cacheNotifications, 1, "LRU touches must not invalidate the offline list")
        cache.removeAll()
        XCTAssertEqual(cache.entries.count, 0)
        XCTAssertEqual(cacheNotifications, 2)
        XCTAssertTrue(try persistence.load().isEmpty, "Read after the serial writer drains")
        await drainMainQueue()

        XCTAssertEqual(appNotifications, 0, "Cache writes must not reevaluate unrelated tabs")
        app.isTabChromeHidden.toggle()
        XCTAssertEqual(appNotifications, 1)
        withExtendedLifetime((appChanges, cacheChanges)) {}
    }

    @MainActor func testReadingProgressWritesDoNotInvalidateTheAppTree() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root),
                                   groupPersistence: BookshelfGroupPersistence(rootURL: root))
        let app = AppState(bookshelfStore: shelf)
        shelf.addOrUpdate(SearchBook(name: "进度测试", author: "作者", coverUrl: nil,
                                     bookUrl: "fixture-book", sourceName: "夹具源",
                                     sourceUrl: "https://fixture.example"))
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let book = try XCTUnwrap(shelf.book(id: "https://fixture.example|fixture-book"))
        var notifications = 0
        let subscription = app.objectWillChange.sink { notifications += 1 }

        shelf.updateReadingProgress(bookID: book.id, chapterIndex: 2, chapterTitle: "第三章",
                                    totalChapters: 12, paragraphIndex: 5)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

        XCTAssertEqual(shelf.book(id: book.id)?.currentChapterIndex, 2,
                       "The progress still has to be persisted for the shelf")
        XCTAssertEqual(notifications, 0,
                       "A progress tick must not re-evaluate the reader body or the other tabs")
        withExtendedLifetime(subscription) {}
    }

    @MainActor func testReadingHistoryChangesPublishLocallyWithoutInvalidatingTheReader() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let history = ReadingHistoryStore(persistence: ReadingHistoryPersistence(rootURL: root))
        let app = AppState(readingHistoryStore: history)
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        var appNotifications = 0
        var counts: [Int] = []
        let appChanges = app.objectWillChange.sink { appNotifications += 1 }
        let historyChanges = history.$history.dropFirst().sink { counts.append($0.count) }
        history.record(bookID: "fixture", title: "历史", author: "", coverURL: nil, sourceName: "",
            sourceURL: "local://text", bookURL: "fixture", intro: nil, chapterIndex: 1, chapterTitle: "第二章")
        await history.waitForPendingWrites()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        XCTAssertTrue(counts.contains(1), "The history screen still receives the new row")
        XCTAssertEqual(appNotifications, 0)
        history.removeAll()
        XCTAssertEqual(counts.last, 0)
        withExtendedLifetime((appChanges, historyChanges)) {}
    }
}
