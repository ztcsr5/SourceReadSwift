import XCTest
@testable import SourceReadSwift

@MainActor
final class ChapterFetchBlockingTests: XCTestCase {
    func testSourceBlocksReturnTheOriginalFailureWithoutAutomaticRetry() async {
        let failures: [SourceEngineError] = [
            .blocked("访问过快，请在1分钟后重试"), .sourceUpdateRequired,
            .network("HTTP 401"), .network("HTTP 403"), .network("HTTP 429"),
            .network("访问过快，请稍后重试"), .network("請求過於頻繁"),
            .javascript("请先登录后重试"), .rule("Cloudflare captcha required")
        ]
        let source = BookSource(bookSourceName: "Blocked fixture", bookSourceUrl: "https://blocked.invalid")
        let chapter = BookChapter(title: "Chapter", url: "https://blocked.invalid/1", bookUrl: "book", index: 0)
        for failure in failures {
            let engine = FailedChapterFetchEngine(failure: failure)
            let result = await ChapterFetchPolicy.fetch(source: source, chapter: chapter, engine: engine)
            XCTAssertEqual(result, .failure(failure))
            let count = await engine.requests
            XCTAssertEqual(count, 1, "Source-level failures require a user action or cooldown, not a retry")
        }
    }
}

private actor FailedChapterFetchEngine: SourceEngine {
    let failure: SourceEngineError
    private(set) var requests = 0

    init(failure: SourceEngineError) { self.failure = failure }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        requests += 1
        return .failure(failure)
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Unused fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}
