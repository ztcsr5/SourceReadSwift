import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterCacheWriterPerformanceTests: XCTestCase {
    func testDiskWriterRunsOffMainAndReloadWaitsForWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let written = expectation(description: "background cache write")
        let entry = ChapterContentCacheEntry(key: "source|1", sourceURL: "source", chapterURL: "1", bookURL: "book",
            title: "Chapter 1", paragraphs: [String(repeating: "正文", count: 10_000)], nextContentUrl: nil,
            purifySignature: "", cachedAt: Date())
        persistence.saveInBackground([entry]) { result in
            XCTAssertFalse(Thread.isMainThread, "Full cache encoding and IO must not run in a scroll/TOC UI callback")
            if case .failure(let error) = result { XCTFail("\(error)") }
            written.fulfill()
        }
        await fulfillment(of: [written], timeout: 5)
        XCTAssertEqual(try persistence.load().first?.paragraphs, entry.paragraphs)
    }

    func testQueuedDownloadTouchAndClearCannotResurrectOldCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapter = BookChapter(title: "1", url: "chapter-1", bookUrl: "book", index: 0)
        store.save(ChapterContent(chapter: chapter, title: "1", paragraphs: ["cached"], nextContentUrl: nil), sourceURL: "source", purifyRules: [])
        store.markRead(sourceURL: "source", chapter: chapter, purifyRules: [])
        store.removeAll()
        // load is a serialization barrier across persistence instances too.
        XCTAssertTrue(try ChapterContentCachePersistence(rootURL: root).load().isEmpty)
        XCTAssertTrue(store.entries.isEmpty)
    }
}
