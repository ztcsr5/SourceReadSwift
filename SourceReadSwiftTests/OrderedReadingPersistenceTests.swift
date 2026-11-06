import XCTest
import Combine
@testable import SourceReadSwift

@MainActor
final class OrderedReadingPersistenceTests: XCTestCase {
    private func makeBooks() -> [BookshelfBook] {
        (0..<2).map { index in
            BookshelfBook(localTextBook: LocalTextBook(title: "Book \(index)", author: "Test",
                chapters: [LocalTextChapter(title: "Chapter", paragraphs: ["Local text"], index: 0)]))
        }
    }

    func testRepeatedBookDetailRefreshPublishesAndWritesOnlyTheChangedSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var book = try XCTUnwrap(makeBooks().first)
        book.latestChapterTitle = "Chapter 5"
        book.totalChapters = 5
        book.seenTotalChapters = 5
        book.currentChapterIndex = 2
        book.currentParagraphIndex = 9
        let initial = BookshelfPersistence(rootURL: root)
        try initial.save([book])
        let write = expectation(description: "Only changed details reach persistence")
        write.assertForOverFulfill = true
        let store = BookshelfStore(persistence: BookshelfPersistence(rootURL: root, writeObserver: { write.fulfill() }))
        var published: [BookshelfBook] = []
        let observation = store.$books.dropFirst().sink { published.append(contentsOf: $0) }
        defer { observation.cancel() }

        for _ in 0..<10 {
            store.updateDetails(bookID: book.id, latestChapterTitle: "Chapter 5", intro: nil, totalChapters: 5)
        }
        XCTAssertTrue(published.isEmpty, "An identical background refresh must not invalidate the reading or shelf tree")
        store.updateDetails(bookID: book.id, latestChapterTitle: "Chapter 6", intro: "New intro", totalChapters: 6)
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(published.first?.currentParagraphIndex, 9)
        XCTAssertEqual(published.first?.seenTotalChapters, 5)
        XCTAssertEqual(published.first?.hasUpdates, true)
        await fulfillment(of: [write], timeout: 5)
        await store.waitForPendingWrites()
        XCTAssertEqual(try initial.load().first?.latestChapterTitle, "Chapter 6")
        XCTAssertEqual(try initial.load().first?.intro, "New intro")
    }

    func testProgressAndSessionEncodingRunOffMainAndReloadNewestPosition() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let seeded = BookshelfPersistence(rootURL: root)
        let books = makeBooks()
        try seeded.save(books)
        let writes = expectation(description: "progress and session writes")
        writes.expectedFulfillmentCount = 3
        let persistence = BookshelfPersistence(rootURL: root, writeObserver: {
            XCTAssertFalse(Thread.isMainThread, "Encoding and filesystem IO must not execute in the UI callback")
            writes.fulfill()
        })
        let store = BookshelfStore(persistence: persistence)
        let start = ProcessInfo.processInfo.systemUptime
        store.updateReadingProgress(bookID: books[0].id, chapterIndex: 7, chapterTitle: "7", totalChapters: 30, paragraphIndex: 2)
        store.updateReadingProgress(bookID: books[0].id, chapterIndex: 9, chapterTitle: "9", totalChapters: 30, paragraphIndex: 5)
        store.recordReadingSession(bookID: books[0].id, duration: 10)
        let enqueueMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        await fulfillment(of: [writes], timeout: 5)
        await store.waitForPendingWrites()
        let loaded = try BookshelfPersistence(rootURL: root).load()
        let book = try XCTUnwrap(loaded.first { $0.id == books[0].id })
        XCTAssertEqual(book.currentChapterIndex, 9)
        XCTAssertEqual(book.currentParagraphIndex, 5)
        XCTAssertEqual(book.readingSessionCount, 1)
        XCTAssertEqual(book.totalReadingSeconds, 10)
        print("Reading persistence enqueueMs=\(enqueueMilliseconds) totalMs=\((ProcessInfo.processInfo.systemUptime - start) * 1000); not device FPS")
    }

    func testRapidBookSwitchPreservesBothPositionsAcrossPersistenceInstances() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(rootURL: root)
        let books = makeBooks()
        try persistence.save(books)
        let store = BookshelfStore(persistence: persistence)
        for index in 0..<40 {
            store.updateReadingProgress(bookID: books[index % 2].id, chapterIndex: index,
                chapterTitle: "\(index)", totalChapters: 50, paragraphIndex: index + 1)
        }
        // This is the same nonblocking drain used by the background boundary.
        await store.waitForPendingWrites()
        let reloaded = BookshelfStore(persistence: BookshelfPersistence(rootURL: root))
        XCTAssertEqual(reloaded.book(id: books[0].id)?.currentChapterIndex, 38)
        XCTAssertEqual(reloaded.book(id: books[0].id)?.currentParagraphIndex, 39)
        XCTAssertEqual(reloaded.book(id: books[1].id)?.currentChapterIndex, 39)
        XCTAssertEqual(reloaded.book(id: books[1].id)?.currentParagraphIndex, 40)
    }

    func testQueuedProgressCannotResurrectADeletedBookOrSidecar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(rootURL: root)
        let book = try XCTUnwrap(makeBooks().first)
        try persistence.save([book])
        let store = BookshelfStore(persistence: persistence)
        store.updateReadingProgress(bookID: book.id, chapterIndex: 12, chapterTitle: "12", totalChapters: 20, paragraphIndex: 4)
        store.remove(bookID: book.id)
        XCTAssertTrue(try BookshelfPersistence(rootURL: root).load().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bookshelf_reading_positions.json").path))
    }

    func testQueuedHistoryCannotOverwriteLaterDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writes = expectation(description: "history writes off main")
        writes.expectedFulfillmentCount = 2
        let queued = ReadingHistoryPersistence(rootURL: root, writeObserver: {
            XCTAssertFalse(Thread.isMainThread)
            writes.fulfill()
        })
        let history = ReadingHistoryStore(persistence: queued)
        let book = try XCTUnwrap(makeBooks().first)
        history.record(book: book)
        history.record(book: book)
        await fulfillment(of: [writes], timeout: 5)
        await history.waitForPendingWrites()
        XCTAssertEqual(try ReadingHistoryPersistence(rootURL: root).load().first?.id, book.id)
        // A plain instance still shares the same ordered disk boundary.
        let deleting = ReadingHistoryStore(persistence: ReadingHistoryPersistence(rootURL: root))
        deleting.record(book: book)
        deleting.removeAll()
        XCTAssertTrue(try ReadingHistoryPersistence(rootURL: root).load().isEmpty)
    }

    func testProgressBurstsPublishOneGlobalSnapshotAndKeepLocalObservation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(rootURL: root)
        let books = makeBooks()
        try persistence.save(books)
        let store = BookshelfStore(persistence: persistence)
        let history = ReadingHistoryStore(persistence: ReadingHistoryPersistence(rootURL: root))
        let app = AppState(bookshelfStore: store, readingHistoryStore: history)
        // Drain initialization before observing a controlled synchronous burst.
        await settleMainQueue()
        var global = 0
        var local = 0
        let globalSubscription = app.objectWillChange.sink { global += 1 }
        let localSubscription = history.objectWillChange.sink { local += 1 }
        for index in 0..<20 {
            store.updateReadingProgress(bookID: books[0].id, chapterIndex: index, chapterTitle: "\(index)", totalChapters: 30)
        }
        await settleMainQueue()
        XCTAssertEqual(global, 1, "Keep subscriptions, coalesce only the global forwarding burst")
        XCTAssertEqual(local, 20, "Each coherent history mutation remains observable locally")
        XCTAssertEqual(history.history.first?.currentChapterIndex, 19)
        await store.waitForPendingWrites()
        await history.waitForPendingWrites()
        await settleMainQueue()
        XCTAssertEqual(global, 1, "Successful writes must not republish unchanged nil errors")
        app.isTabChromeHidden.toggle()
        XCTAssertEqual(global, 2, "Navigation state remains immediate")
        withExtendedLifetime((globalSubscription, localSubscription)) {}
    }

    func testSessionWithPinnedBooksRecordsTheActualReaderBook() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        var books = makeBooks()
        books[0].isPinned = true
        let persistence = BookshelfPersistence(rootURL: root)
        try persistence.save(books)
        let store = BookshelfStore(persistence: persistence)
        var recordedID: String?
        store.onBookRead = { recordedID = $0.id }
        store.recordReadingSession(bookID: books[1].id, duration: 15)
        XCTAssertEqual(recordedID, books[1].id)
        XCTAssertEqual(store.books.first?.id, books[0].id)
        await store.waitForPendingWrites()
        XCTAssertEqual(try persistence.load().first { $0.id == books[1].id }?.totalReadingSeconds, 15)
    }

    func testWriteFailureIsReportedAndNewerSuccessfulPositionRecovers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        // A file cannot act as a persistence directory: deterministic real IO failure.
        try Data("blocked".utf8).write(to: root)
        let persistence = BookshelfPersistence(rootURL: root)
        let store = BookshelfStore(persistence: persistence)
        store.addLocalTextBook(LocalTextBook(title: "Retry", author: "Test",
            chapters: [LocalTextChapter(title: "1", paragraphs: ["text"], index: 0)]))
        let id = try XCTUnwrap(store.books.first?.id)
        let failed = expectation(description: "async progress failure is reported")
        let failureSubscription = store.$lastError.dropFirst().compactMap { $0 }.prefix(1).sink { _ in failed.fulfill() }
        store.updateReadingProgress(bookID: id, chapterIndex: 2, chapterTitle: "2", totalChapters: 10, paragraphIndex: 3)
        await fulfillment(of: [failed], timeout: 5)
        await store.waitForPendingWrites()
        await settleMainQueue()
        XCTAssertNotNil(store.lastError)
        try FileManager.default.removeItem(at: root)
        let recovered = expectation(description: "newer successful snapshot clears the error")
        let recoverySubscription = store.$lastError.dropFirst().filter { $0 == nil }.prefix(1).sink { _ in recovered.fulfill() }
        // A full save installs the canonical book after the path is repaired.
        store.recordReadingSession(bookID: id, duration: 5)
        store.updateReadingProgress(bookID: id, chapterIndex: 4, chapterTitle: "4", totalChapters: 10, paragraphIndex: 8)
        await fulfillment(of: [recovered], timeout: 5)
        await store.waitForPendingWrites()
        await settleMainQueue()
        XCTAssertNil(store.lastError)
        let loaded = try XCTUnwrap(persistence.load().first)
        XCTAssertEqual(loaded.currentChapterIndex, 4)
        XCTAssertEqual(loaded.currentParagraphIndex, 8)
        withExtendedLifetime((failureSubscription, recoverySubscription)) {}
    }

    private func settleMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
