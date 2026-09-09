import XCTest
@testable import SourceReadSwift

@MainActor
final class ReadingHistoryStoreTests: XCTestCase {
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
