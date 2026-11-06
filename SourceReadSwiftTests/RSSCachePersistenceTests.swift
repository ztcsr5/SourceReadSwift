import XCTest
@testable import SourceReadSwift

final class RSSCachePersistenceTests: XCTestCase {
    @MainActor func testWritesStayOffMainAndClearWinsOverEarlierSnapshots() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let writes = expectation(description: "Every queued snapshot was written")
        writes.expectedFulfillmentCount = 3
        let cache = RSSCacheFile<[String]>(url: root.appendingPathComponent("feed.json"), onWrite: {
            XCTAssertFalse(Thread.isMainThread)
            writes.fulfill()
        })
        cache.save(["first"])
        cache.save(["second"])
        cache.save([])
        await cache.waitForPendingWrites()
        await fulfillment(of: [writes], timeout: 2)
        XCTAssertEqual(try cache.load(), [])
    }

    @MainActor func testNegativeCacheLimitsRemainEmptyWithoutCrashing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let article = RSSArticlePreview(title: "A", link: "https://fixture.invalid/a", pubDate: nil, description: nil)
        let feed = RSSFeedCacheStore(fileURL: root.appendingPathComponent("feed.json"), maxSources: -1)
        let content = RSSArticleContentCacheStore(fileURL: root.appendingPathComponent("content.json"), maxEntries: -1)
        feed.save([article], sourceURL: "https://fixture.invalid/feed")
        content.save(["body"], for: article)
        await feed.waitForPendingWrites()
        await content.waitForPendingWrites()
        XCTAssertTrue(feed.entries.isEmpty)
        XCTAssertTrue(content.entries.isEmpty)
        XCTAssertTrue(RSSFeedCacheStore(fileURL: root.appendingPathComponent("feed.json")).entries.isEmpty)
        XCTAssertTrue(RSSArticleContentCacheStore(fileURL: root.appendingPathComponent("content.json")).entries.isEmpty)
    }
}
