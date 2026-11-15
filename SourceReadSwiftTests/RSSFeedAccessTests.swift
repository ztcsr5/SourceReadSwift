import XCTest
@testable import SourceReadSwift

final class RSSFeedAccessTests: XCTestCase {
    private let subscription = "https://feed.invalid/follow"
    private let returnedURL = URL(string: "https://journal.invalid/updates/feed.xml")!
    private let atom = """
        <?xml version="1.0"?>
        <feed xmlns="http://www.w3.org/2005/Atom"><title>今日书讯</title>
        <entry><id>dispatch-1</id><title>新文章</title><link href="entry/1"/></entry>
        </feed>
        """

    @MainActor
    func testDirectFeedURLIsRecognizedAndDoesNotReplaceExistingPreferences() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SourceStore(persistence: SourcePersistence(rootURL: directory))
        let downloader = FeedImportFixture(payload: response(atom))
        let report = try await store.importSmartInputAsync(subscription, downloader: downloader).report
        XCTAssertEqual(report.addedRSSSources, 1)
        XCTAssertEqual(report.addedBookSources, 0)
        let source = try XCTUnwrap(store.rssSources.first)
        XCTAssertEqual(source.sourceName, "今日书讯")
        XCTAssertEqual(source.sourceUrl, subscription)
        store.setRSSEnabled(false, for: [subscription])
        let duplicate = try await store.importSmartInputAsync(subscription, downloader: downloader).report
        XCTAssertEqual(duplicate.ignored, 1)
        XCTAssertEqual(store.rssSources.first?.enabled, false)
    }

    func testRedirectResolvesRelativeArticleLinkWithoutChangingSubscriptionIdentity() async throws {
        let loader = RSSFeedLoader(client: FeedNetworkFixture(response: response(atom)))
        let articles = try await loader.load(RSSSource(sourceName: "Fixture", sourceUrl: subscription))
        XCTAssertEqual(articles.map(\.id), [subscription + "|dispatch-1"])
        XCTAssertEqual(articles.first?.link, "https://journal.invalid/updates/entry/1")
    }

    func testArticleRulesCanReadHTMLAndJSONAndAnUnrelatedPageIsAnError() async throws {
        let source = RSSSource(sourceName: "Fixture", sourceUrl: subscription, ruleArticles: "article",
                               ruleTitle: "h2@text", ruleLink: "a@href")
        let html = response("<html><article><h2>子目录</h2><a href='one'>阅读全文</a></article></html>")
        let articles = try await RSSFeedLoader(client: FeedNetworkFixture(response: html)).load(source)
        XCTAssertEqual(articles.first?.title, "子目录")
        XCTAssertEqual(articles.first?.link, "https://journal.invalid/updates/one")

        let jsonSource = RSSSource(sourceName: "Fixture", sourceUrl: subscription,
                                   ruleArticles: "$.items[*]", ruleTitle: "$.title", ruleLink: "$.share")
        let json = response(#"{"items":[{"title":"一则","share":"/article/one"}]}"#)
        let entries = try await RSSFeedLoader(client: FeedNetworkFixture(response: json)).load(jsonSource)
        XCTAssertEqual(entries.map(\.link), ["https://journal.invalid/article/one"])

        let unrelated = RSSSource(sourceName: "RSS only", sourceUrl: subscription)
        do {
            _ = try await RSSFeedLoader(client: FeedNetworkFixture(response: html)).load(unrelated)
            XCTFail("An HTML page must not erase the previous RSS cache")
        } catch let issue as RSSFeedLoader.Issue {
            XCTAssertEqual(issue, .notAFeed)
        }
    }

    private func response(_ body: String) -> SourceResponse {
        SourceResponse(url: returnedURL, statusCode: 200, headers: [:], body: body, data: Data(body.utf8))
    }
}

private struct FeedNetworkFixture: SourceNetworkClient {
    let response: SourceResponse

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        .success(response)
    }
}

private struct FeedImportFixture: SourceImportDownloading {
    let payload: SourceResponse

    func download(from rawURL: String) async -> Result<SourceImportPayload, SourceImportError> {
        .success(.init(url: payload.url, statusCode: payload.statusCode, headers: payload.headers,
                       data: payload.data, text: payload.body))
    }
}
