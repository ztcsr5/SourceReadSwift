import XCTest
@testable import SourceReadSwift

@MainActor
final class ReadingHistoryStoreTests: XCTestCase {
    func testUnshelvedReadingCanBeResumedAfterHistoryReloadWithoutAddingToShelf() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { if FileManager.default.fileExists(atPath: folder.path) { try? FileManager.default.removeItem(at: folder) } }
        let persistence = ReadingHistoryPersistence(rootURL: folder)
        let store = ReadingHistoryStore(persistence: persistence)
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: folder),
            groupPersistence: BookshelfGroupPersistence(rootURL: folder))
        let app = AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: folder)),
            bookshelfStore: shelf, readingHistoryStore: store)
        let book = SearchBook(name: "未收藏的书", author: "纸间", coverUrl: nil,
            bookUrl: "https://history.fixture.invalid/book", sourceName: "Fixture", sourceUrl: "https://history.fixture.invalid")
        app.recordUnshelvedReading(BookshelfBook(searchBook: book), at: .init(bookID: book.id, chapterIndex: 99,
            chapterTitle: "第 100 章", paragraphIndex: 7), totalChapters: 101)
        await shelf.waitForPendingWrites()
        await store.waitForPendingWrites()
        let resumed = try XCTUnwrap(ReadingHistoryStore(persistence: persistence).history.first).asBookshelfBook
        XCTAssertFalse(shelf.contains(book))
        XCTAssertEqual(resumed.id, book.id)
        XCTAssertEqual(resumed.currentChapterIndex, 99)
        XCTAssertEqual(resumed.currentParagraphIndex, 7)
    }

    func testRecordsAndPersistsReadingHistoryIndependently() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let persistence = ReadingHistoryPersistence(fileManager: .default, rootURL: tempRoot)
        let store = ReadingHistoryStore(persistence: persistence)

        XCTAssertTrue(store.history.isEmpty)

        store.record(
            bookID: "test-book-1",
            title: "斗破苍穹",
            author: "天蚕土豆",
            coverURL: "https://example.com/cover.jpg",
            sourceName: "笔趣阁",
            sourceURL: "https://example.com",
            bookURL: "https://example.com/book/1",
            intro: "这里是简介",
            chapterIndex: 5,
            chapterTitle: "第六章 炼药师",
            paragraphIndex: 2,
            totalChapters: 100,
            sessionDuration: 120,
            incrementSession: true
        )

        XCTAssertEqual(store.history.count, 1)
        let item = try XCTUnwrap(store.history.first)
        XCTAssertEqual(item.id, "test-book-1")
        XCTAssertEqual(item.title, "斗破苍穹")
        XCTAssertEqual(item.currentChapterIndex, 5)
        XCTAssertEqual(item.currentChapterTitle, "第六章 炼药师")
        XCTAssertEqual(item.currentParagraphIndex, 2)
        XCTAssertEqual(item.totalReadingSeconds, 120)
        XCTAssertEqual(item.readingSessionCount, 1)

        // Reload from disk
        let reloaded = ReadingHistoryStore(persistence: persistence)
        XCTAssertEqual(reloaded.history.count, 1)
        XCTAssertEqual(reloaded.history.first?.title, "斗破苍穹")

        // Update progress on existing book
        store.record(
            bookID: "test-book-1",
            title: "斗破苍穹",
            author: "天蚕土豆",
            coverURL: "https://example.com/cover.jpg",
            sourceName: "笔趣阁",
            sourceURL: "https://example.com",
            bookURL: "https://example.com/book/1",
            intro: "这里是简介",
            chapterIndex: 10,
            chapterTitle: "第十一章 突破",
            paragraphIndex: 0,
            totalChapters: 100,
            sessionDuration: 60,
            incrementSession: true
        )

        XCTAssertEqual(store.history.count, 1)
        let updated = try XCTUnwrap(store.history.first)
        XCTAssertEqual(updated.currentChapterIndex, 10)
        XCTAssertEqual(updated.totalReadingSeconds, 180)
        XCTAssertEqual(updated.readingSessionCount, 2)

        // Delete item
        store.remove(id: "test-book-1")
        XCTAssertTrue(store.history.isEmpty)

        try? FileManager.default.removeItem(at: tempRoot)
    }
}
