import Combine
import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterCacheWriterPerformanceTests: XCTestCase {
    func testLRUTouchPublishesOneCompleteCacheSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let store = ChapterContentCacheStore(persistence: persistence)
        let chapters = (0...1).map { BookChapter(title: "\($0)", url: "chapter-\($0)", bookUrl: "book", index: $0) }
        for chapter in chapters {
            store.save(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["正文"], nextContentUrl: nil),
                sourceURL: "source", purifyRules: [])
        }
        var published: [[String]] = []
        let subscription = store.$entries.dropFirst().sink { published.append($0.map(\.chapterURL)) }
        defer { subscription.cancel() }
        store.markRead(sourceURL: "source", chapter: chapters[0], purifyRules: [])
        XCTAssertEqual(published, [["chapter-0", "chapter-1"]])
        XCTAssertEqual(try persistence.load().map(\.chapterURL), ["chapter-0", "chapter-1"])
    }

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
