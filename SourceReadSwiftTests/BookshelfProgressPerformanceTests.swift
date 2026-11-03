import XCTest
@testable import SourceReadSwift

@MainActor
final class BookshelfProgressPerformanceTests: XCTestCase {
    func testOpeningAndClearingUpdateBadgeDoesNotRewriteBookText() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(rootURL: root)
        let store = BookshelfStore(persistence: persistence)
        store.addLocalTextBook(LocalTextBook(title: "Local", author: "Test", chapters: [
            LocalTextChapter(title: "1", paragraphs: ["text"], index: 0)
        ]))
        let id = try XCTUnwrap(store.books.first?.id)
        store.updateDetails(bookID: id, latestChapterTitle: "2", intro: nil, totalChapters: 2)
        let canonical = root.appendingPathComponent("bookshelf_books.json")
        let before = try Data(contentsOf: canonical)
        store.markReaderOpened(bookID: id)
        store.markUpdatesSeen(bookID: id)
        store.markUpdatesSeen(bookID: id)
        await store.waitForPendingWrites()
        XCTAssertEqual(try Data(contentsOf: canonical), before)
        XCTAssertEqual(try persistence.load().first?.seenTotalChapters, 2)
    }
    func testProgressWriteDoesNotRewriteLocalBookTextAndReloadsImmediately() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(rootURL: root)
        let store = BookshelfStore(persistence: persistence)
        store.addLocalTextBook(LocalTextBook(title: "Large local book", author: "Test", chapters:
            (0..<850).map { LocalTextChapter(title: "第\($0 + 1)章", paragraphs: [String(repeating: "本地正文", count: 400)], index: $0) }))
        let id = try XCTUnwrap(store.books.first?.id)
        let canonicalURL = root.appendingPathComponent("bookshelf_books.json")
        let before = try Data(contentsOf: canonicalURL)
        let start = Date()
        store.updateReadingProgress(bookID: id, chapterIndex: 172, chapterTitle: "目标章", totalChapters: 850, paragraphIndex: 3)
        // Reopening is a FIFO durability barrier; direct filesystem reads do not await a queued save.
        let reloaded = BookshelfStore(persistence: persistence)
        XCTAssertEqual(try Data(contentsOf: canonicalURL), before, "Interactive progress must not encode/write the multi-MB book again")
        let sidecar = try Data(contentsOf: root.appendingPathComponent("bookshelf_reading_positions.json"))
        XCTAssertLessThan(sidecar.count, 2_048)
        XCTAssertEqual(reloaded.book(id: id)?.currentChapterIndex, 172)
        XCTAssertEqual(reloaded.book(id: id)?.currentParagraphIndex, 3)
        XCTAssertEqual(reloaded.book(id: id)?.currentChapterTitle, "目标章")
        XCTAssertEqual(reloaded.book(id: id)?.localChapters?.count, 850)
        print("Progress canonicalBytes=\(before.count) sidecarBytes=\(sidecar.count) elapsedIncludingReload=\(Date().timeIntervalSince(start))")
    }

    func testFullSaveFoldsProgressAndClearsSidecar() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(rootURL: root)
        let store = BookshelfStore(persistence: persistence)
        store.addLocalTextBook(LocalTextBook(title: "Local", author: "Test", chapters: [LocalTextChapter(title: "1", paragraphs: ["text"], index: 0)]))
        let id = try XCTUnwrap(store.books.first?.id)
        store.updateReadingProgress(bookID: id, chapterIndex: 0, chapterTitle: "1", totalChapters: 1, paragraphIndex: 2)
        store.recordReadingSession(bookID: id, duration: 5)
        let folded = try persistence.load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bookshelf_reading_positions.json").path))
        XCTAssertEqual(folded.first?.currentParagraphIndex, 2)
        store.updateReadingProgress(bookID: id, chapterIndex: 0, chapterTitle: "1", totalChapters: 1)
        store.remove(bookID: id)
        XCTAssertTrue(try persistence.load().isEmpty)
    }

    func testBrokenProgressSidecarDoesNotHideValidBooks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = BookshelfPersistence(rootURL: root)
        let store = BookshelfStore(persistence: persistence)
        store.addLocalTextBook(LocalTextBook(title: "Local", author: "Test", chapters: [LocalTextChapter(title: "1", paragraphs: ["text"], index: 0)]))
        try Data("broken".utf8).write(to: root.appendingPathComponent("bookshelf_reading_positions.json"))
        XCTAssertEqual(try persistence.load().count, 1)
    }
}
