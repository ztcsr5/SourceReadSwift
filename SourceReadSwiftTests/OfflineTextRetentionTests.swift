import XCTest
@testable import SourceReadSwift

@MainActor
final class OfflineTextRetentionTests: XCTestCase {
    func testOfflineEditionsSeparateDifferentSourcesSharingTheSameBookURL() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        cache.save(chapter(0), sourceURL: "source-b", purifyRules: [], retainOffline: true)
        cache.save(chapter(0), sourceURL: "source-a", purifyRules: [], retainOffline: true)
        cache.save(chapter(1), sourceURL: "source-a", purifyRules: [], retainOffline: true)
        try await cache.flush()

        let editions = OfflineChapterEdition.group(cache.entries)
        XCTAssertEqual(editions.map(\.id.sourceURL), ["source-a", "source-b"])
        XCTAssertEqual(Set(editions.map(\.id.bookURL)), ["https://book.invalid"])
        XCTAssertEqual(editions.map { $0.entries.compactMap(\.chapterIndex).sorted() }, [[0, 1], [0]])
        XCTAssertTrue(editions.allSatisfy { edition in
            edition.entries.allSatisfy { $0.sourceURL == edition.id.sourceURL }
        })
    }

    func testExplicitDownloadsSurviveLRUEvictionAndRelaunch() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = ChapterContentCachePersistence(rootURL: root)
        let cache = ChapterContentCacheStore(persistence: persistence, maxEntryCount: 2)
        for index in 0..<5 {
            cache.save(chapter(index), sourceURL: "https://source.invalid", purifyRules: [], retainOffline: true)
        }
        for index in 5..<9 { cache.save(chapter(index), sourceURL: "https://source.invalid", purifyRules: []) }
        try await cache.flush()
        let reopened = ChapterContentCacheStore(persistence: persistence, maxEntryCount: 2)
        for index in 0..<5 {
            XCTAssertNotNil(reopened.content(sourceURL: "https://source.invalid", chapter: chapter(index).chapter, purifyRules: []))
        }
        XCTAssertEqual(reopened.entries.filter { $0.isOffline != true }.count, 2)
        reopened.removeAll()
        try await reopened.flush()
        XCTAssertTrue(ChapterContentCacheStore(persistence: persistence).entries.isEmpty)
    }

    func testReadingAndRefreshingAnOfflineChapterPreservesItsRetention() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root), maxEntryCount: 1)
        let first = chapter(0)
        cache.save(first, sourceURL: "source", purifyRules: [], retainOffline: true)
        cache.markRead(sourceURL: "source", chapter: first.chapter, purifyRules: [])
        cache.save(first, sourceURL: "source", purifyRules: ["updated"])
        cache.save(chapter(1), sourceURL: "source", purifyRules: [])
        cache.save(chapter(2), sourceURL: "source", purifyRules: [])
        cache.removeExpired(olderThanDays: -1)
        try await cache.flush()
        XCTAssertEqual(cache.entries.count, 1)
        XCTAssertEqual(cache.entries.first?.chapterIndex, 0)
        XCTAssertEqual(cache.entries.first?.isOffline, true)
    }

    private func chapter(_ index: Int) -> ChapterContent {
        ChapterContent(chapter: BookChapter(title: "第\(index)章", url: "https://book.invalid/\(index)",
            bookUrl: "https://book.invalid", index: index, isVip: false), title: "第\(index)章", paragraphs: ["离线正文"])
    }
}
