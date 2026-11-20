import Foundation
import XCTest
@testable import SourceReadSwift

final class SourceContentPaginationFailureTests: XCTestCase {
    func testRateLimitOnNextPageDoesNotReturnPartialChapterSuccess() async {
        let notice = "您的账号因访问过快已被暂时封禁，请在1分钟后重试。也可以开通VIP解除访问限制。"
        let secondPage = Self.response(body: ["content": notice])
        let (result, requests) = await load(secondPage: .success(secondPage))

        guard case .failure(.blocked(let message)) = result else {
            return XCTFail("Expected rate limit failure instead of partial chapter: \(result)")
        }
        XCTAssertTrue(message.contains("1分钟后重试"))
        XCTAssertEqual(requests, Self.pageURLs)
    }

    func testUpdateNoticeOnNextPageDoesNotReturnPartialChapterSuccess() async {
        let secondPage = Self.response(body: ["content": "您的书源版本过低，请更新书源"])
        let (result, requests) = await load(secondPage: .success(secondPage))

        guard case .failure(.sourceUpdateRequired) = result else {
            return XCTFail("Expected source update failure: \(result)")
        }
        XCTAssertEqual(requests, Self.pageURLs)
    }

    func testAuthenticationAndRateLimitHTTPFailuresPropagateFromNextPage() async {
        for status in [401, 403, 429] {
            let (result, requests) = await load(secondPage: .success(Self.response(status: status, body: [:])))
            guard case .failure(.network(let message)) = result else {
                XCTFail("Expected HTTP \(status) failure: \(result)")
                continue
            }
            XCTAssertEqual(message, "HTTP \(status)")
            XCTAssertEqual(requests, Self.pageURLs)
        }
    }

    func testExplicitSourceBlockFromNextPageTransportPropagates() async {
        let (result, requests) = await load(secondPage: .failure(.blocked("请先完成验证")))
        guard case .failure(.blocked("请先完成验证")) = result else {
            return XCTFail("Expected original block error: \(result)")
        }
        XCTAssertEqual(requests, Self.pageURLs)
    }

    func testTransientAndSinglePageFailuresRetainExistingContinuationBehavior() async throws {
        let errors: [SourceEngineError] = [.network("请求超时"), .network("HTTP 404")]
        for error in errors {
            let (result, requests) = await load(secondPage: .failure(error))
            let content = try result.get()
            XCTAssertEqual(content.paragraphs, [Self.firstParagraph])
            XCTAssertEqual(content.nextContentUrl, Self.pageURLs[1])
            XCTAssertEqual(requests, Self.pageURLs)
        }
    }

    func testSuccessfulNextPageStillCompletesChapter() async throws {
        let (result, requests) = await load(secondPage: .success(Self.response(body: ["content": "第二页人物走进了山谷。"])))
        let content = try result.get()
        XCTAssertEqual(content.paragraphs, [Self.firstParagraph, "第二页人物走进了山谷。"])
        XCTAssertNil(content.nextContentUrl)
        XCTAssertEqual(requests, Self.pageURLs)
    }

    func testCatalogNextPageSourceBlockDoesNotBecomePartialCatalogSuccess() async {
        let failures: [SourceEngineError] = [.network("HTTP 401"), .network("HTTP 429"), .blocked("源站暂时封禁")]
        for error in failures {
            let bytes = Data(#"{"chapters":[{"title":"第一章","url":"/book/chapter-1"}],"next":"https://pagination.fixture.invalid/chapter?page=2"}"#.utf8)
            let first = SourceResponse(url: URL(string: Self.pageURLs[0])!, statusCode: 200,
                headers: ["Content-Type": "application/json"], body: String(decoding: bytes, as: UTF8.self), data: bytes)
            let network = ContentPaginationFailureNetwork(firstPage: first, secondPage: .failure(error))
            let source = BookSource(bookSourceName: "Catalog failure fixture", bookSourceUrl: "https://pagination.fixture.invalid",
                ruleToc: SourceRule(fields: ["chapterList": "$.chapters", "chapterName": "$.title",
                                             "chapterUrl": "$.url", "nextTocUrl": "$.next"]))
            let book = BookDetail(name: "分页样本", author: nil, coverUrl: nil, bookUrl: "https://pagination.fixture.invalid/book",
                tocUrl: Self.pageURLs[0], sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
            let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil))
            engine.allowWebViewFallback = false

            let result = await engine.getChapterList(source: source, book: book)

            guard case .failure(let actual) = result else {
                XCTFail("Expected original catalog block instead of partial success: \(result)")
                continue
            }
            XCTAssertEqual(actual, error)
            let requests = await network.recordedURLs()
            XCTAssertEqual(requests, Self.pageURLs)
        }
    }

    private static let firstParagraph = "第一页人物离开旧城，沿着河流继续向前。"
    private static let pageURLs = [
        "https://pagination.fixture.invalid/chapter",
        "https://pagination.fixture.invalid/chapter?page=2"
    ]

    private static func response(status: Int = 200, body: [String: String]) -> SourceResponse {
        let bytes = try! JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return SourceResponse(url: URL(string: pageURLs[1])!, statusCode: status,
            headers: ["Content-Type": "application/json"], body: String(decoding: bytes, as: UTF8.self), data: bytes)
    }

    private func load(secondPage: Result<SourceResponse, SourceEngineError>) async
        -> (Result<ChapterContent, SourceEngineError>, [String]) {
        let firstBytes = try! JSONSerialization.data(withJSONObject: ["content": Self.firstParagraph, "next": Self.pageURLs[1]])
        let firstPage = SourceResponse(url: URL(string: Self.pageURLs[0])!, statusCode: 200,
            headers: ["Content-Type": "application/json"], body: String(decoding: firstBytes, as: UTF8.self), data: firstBytes)
        let network = ContentPaginationFailureNetwork(firstPage: firstPage, secondPage: secondPage)
        let source = BookSource(bookSourceName: "Pagination failure fixture", bookSourceUrl: "https://pagination.fixture.invalid",
            ruleContent: SourceRule(fields: ["content": "$.content", "nextContentUrl": "$.next"]))
        let chapter = BookChapter(title: "第一章", url: Self.pageURLs[0], bookUrl: "https://pagination.fixture.invalid/book", index: 0)
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil),
            scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        engine.allowWebViewFallback = false
        let result = await engine.getContent(source: source, chapter: chapter)
        return (result, await network.recordedURLs())
    }
}

private actor ContentPaginationFailureNetwork: SourceNetworkClient {
    private let firstPage: SourceResponse
    private let secondPage: Result<SourceResponse, SourceEngineError>
    private var urls: [String] = []

    init(firstPage: SourceResponse, secondPage: Result<SourceResponse, SourceEngineError>) {
        self.firstPage = firstPage
        self.secondPage = secondPage
    }

    func recordedURLs() -> [String] { urls }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        urls.append(request.url.absoluteString)
        if request.url == firstPage.url { return .success(firstPage) }
        guard request.url.absoluteString == firstPage.url.absoluteString + "?page=2", urls.count == 2 else {
            return .failure(.invalidSource("Unexpected pagination fixture request"))
        }
        return secondPage
    }
}
