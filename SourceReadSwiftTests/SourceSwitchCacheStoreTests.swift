import XCTest
@testable import SourceReadSwift

@MainActor
final class SourceSwitchCacheStoreTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceSwitchCacheStoreTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeBook(name: String) -> SearchBook {
        SearchBook(
            name: name,
            author: "作者",
            coverUrl: "https://example.com/cover.jpg",
            bookUrl: "https://example.com/book/1",
            sourceName: "测试源",
            sourceUrl: "https://example.com"
        )
    }

    func testRoundTripThroughDisk() throws {
        let directory = try makeDirectory()
        let fileURL = directory.appendingPathComponent("cache.json")
        let store = SourceSwitchCacheStore(fileURL: fileURL, ttl: 3600)
        let candidate = SourceSwitchCacheStore.Candidate(
            sourceURL: "https://example.com",
            sourceName: "测试源",
            book: makeBook(name: "书名")
        )

        store.save(title: "书名", author: "作者", candidates: [candidate])

        let reloaded = SourceSwitchCacheStore(fileURL: fileURL, ttl: 3600)
        let restored = reloaded.candidates(title: "书名", author: "作者")
        XCTAssertEqual(restored?.count, 1)
        XCTAssertEqual(restored?.first?.book.name, "书名")
        XCTAssertEqual(restored?.first?.sourceName, "测试源")
    }

    func testExpiredEntryIsDropped() throws {
        let directory = try makeDirectory()
        let fileURL = directory.appendingPathComponent("cache.json")
        let store = SourceSwitchCacheStore(fileURL: fileURL, ttl: -1)
        store.save(
            title: "书名",
            author: "作者",
            candidates: [
                SourceSwitchCacheStore.Candidate(
                    sourceURL: "https://example.com",
                    sourceName: "测试源",
                    book: makeBook(name: "书名")
                )
            ]
        )
        XCTAssertNil(store.candidates(title: "书名", author: "作者"))
    }

    func testEmptyCandidateListIsNotPersisted() throws {
        let directory = try makeDirectory()
        let fileURL = directory.appendingPathComponent("cache.json")
        let store = SourceSwitchCacheStore(fileURL: fileURL, ttl: 3600)
        store.save(title: "书名", author: "作者", candidates: [])
        XCTAssertNil(store.candidates(title: "书名", author: "作者"))
    }

    func testKeyNormalisesWidthAndCase() {
        let left = SourceSwitchCacheStore.key(title: "ＴＥＳＴ 书名", author: "Author")
        let right = SourceSwitchCacheStore.key(title: "test书名", author: "author")
        XCTAssertEqual(left, right)
    }
}
