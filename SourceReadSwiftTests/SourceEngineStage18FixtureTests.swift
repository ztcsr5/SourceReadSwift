import XCTest
@testable import SourceReadSwift

/// Stage 18 pagination and failure-observation coverage. Fixtures never leave
/// the process and the client records every request for exact stop assertions.
final class SourceEngineStage18FixtureTests: XCTestCase {
    func testTOCPaginationStopsOnDuplicateURLAndKeepsPrefix() async throws {
        let source = paginationSource()
        let first = "https://fixture.local/toc/1"
        let second = "https://fixture.local/toc/2"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div class='chapter'><a href='/chapter/1'>一</a></div><a class='next' href='/toc/2'>next</a>"),
            second: html("<div class='chapter'><a href='/chapter/2'>二</a></div><a class='next' href='/toc/2'>next</a>")
        ])
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let detail = BookDetail(name: "Paged", author: nil, coverUrl: nil, bookUrl: "https://fixture.local/book", tocUrl: first, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)

        let result = await engine.getChapterList(source: source, book: detail)
        guard case .success(let chapters) = result else { return XCTFail("expected chapters: \(result)") }
        XCTAssertEqual(chapters.map(\.title), ["一", "二"])
        XCTAssertEqual(network.requestedURLs, [first, second])
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "toc.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "duplicate-url")
        XCTAssertEqual(stop.details["pagesLoaded"], "2")
        XCTAssertEqual(stop.details["retainedItemCount"], "2")
    }

    func testTOCPaginationStopsOnCanonicalDuplicateURL() async throws {
        let source = paginationSource()
        let first = "https://fixture.local/toc/1"
        let second = "https://fixture.local/toc/2?b=2&a=1"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div class='chapter'><a href='/chapter/1'>一</a></div><a class='next' href='/toc/2?b=2&a=1'>next</a>"),
            second: html("<div class='chapter'><a href='/chapter/2'>二</a></div><a class='next' href='HTTPS://FIXTURE.LOCAL:443/toc/2?a=1&b=2#reader'>next</a>")
        ])
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let detail = BookDetail(name: "Paged", author: nil, coverUrl: nil, bookUrl: "https://fixture.local/book", tocUrl: first, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)

        let result = await engine.getChapterList(source: source, book: detail)
        guard case .success(let chapters) = result else { return XCTFail("expected chapters: \(result)") }
        XCTAssertEqual(chapters.map(\.title), ["一", "二"])
        XCTAssertEqual(network.requestedURLs, [first, second])
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "toc.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "duplicate-url")
        XCTAssertEqual(stop.details["canonicalURL"], "https://fixture.local/toc/2?a=1&b=2")
    }

    func testTOCPaginationReportsEmptyPageAndRetainsPrefix() async throws {
        let source = paginationSource()
        let first = "https://fixture.local/toc/1"
        let second = "https://fixture.local/toc/2"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div class='chapter'><a href='/chapter/1'>一</a></div><a class='next' href='/toc/2'>next</a>"),
            second: html("<div class='chapter'></div>")
        ])
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let detail = BookDetail(name: "Paged", author: nil, coverUrl: nil, bookUrl: "https://fixture.local/book", tocUrl: first, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)

        let result = await engine.getChapterList(source: source, book: detail)
        guard case .success(let chapters) = result else { return XCTFail("expected prefix: \(result)") }
        XCTAssertEqual(chapters.map(\.title), ["一"])
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "toc.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "empty-page")
        XCTAssertEqual(stop.details["attemptedURL"], second)
        XCTAssertEqual(stop.details["retainedItemCount"], "1")
    }

    func testContentPaginationReportsLoadFailureAndRetainsPrefix() async throws {
        let source = paginationSource()
        let first = "https://fixture.local/content/1"
        let second = "https://fixture.local/content/2"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div id='content'>页一</div><a class='next' href='/content/2'>next</a>")
        ])
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let chapter = BookChapter(title: "Chapter", url: first, bookUrl: "https://fixture.local/book", index: 0, isVip: false)

        let result = await engine.getContent(source: source, chapter: chapter)
        guard case .success(let content) = result else { return XCTFail("expected prefix: \(result)") }
        XCTAssertEqual(content.paragraphs, ["页一"])
        XCTAssertEqual(content.nextContentUrl, second)
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "content.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "load-failure")
        XCTAssertEqual(stop.details["attemptedURL"], second)
        XCTAssertEqual(stop.details["retainedItemCount"], "1")
    }

    func testComicContinuationFailureKeepsThePrefixAndARefreshRestoresPageOrder() async throws {
        let first = "https://fixture.local/comic/chapter?p=1"
        let second = "https://fixture.local/comic/chapter?p=2"
        let source = BookSource(bookSourceName: "Comic pagination", bookSourceUrl: "https://fixture.local",
                                bookSourceType: 2, ruleContent: SourceRule(fields: [
                                    "content": "#content@html", "nextContentUrl": "a.next@href"
                                ]))
        let chapter = BookChapter(title: "Comic", url: first, bookUrl: "https://fixture.local/comic", index: 0)
        let prefix = html("<div id='content'><img data-src='/img/01.webp'></div><a class='next' href='/comic/chapter?p=2'>next</a>")
        let continuation = html("<div id='content'><img src='/img/02.webp'></div>")
        let rejected = Stage18FixtureNetwork(responses: [first: prefix], failures: [second: .network("HTTP 422")])
        let incomplete = try await LegadoSourceEngine(network: rejected).getContent(source: source, chapter: chapter).get()
        let partial = ComicChapterResources(content: incomplete)
        XCTAssertEqual(partial.pages.map(\.url), ["https://fixture.local/img/01.webp"])
        XCTAssertEqual(incomplete.nextContentUrl, second)
        XCTAssertFalse(partial.canReuseFromCache)
        XCTAssertEqual(rejected.requestedURLs, [first, second])

        let recovered = Stage18FixtureNetwork(responses: [first: prefix, second: continuation])
        let complete = try await LegadoSourceEngine(network: recovered).getContent(source: source, chapter: chapter).get()
        let resources = ComicChapterResources(content: complete)
        XCTAssertTrue(resources.canReuseFromCache)
        XCTAssertEqual(resources.pages.map(\.url), ["https://fixture.local/img/01.webp", "https://fixture.local/img/02.webp"])
        XCTAssertEqual(recovered.requestedURLs, [first, second])
    }

    func testComicChapterIdentifiesAStreamingPlaylistWithoutFetchingItsSegments() async {
        let bookURL = "https://fixture.local/comic"
        let source = BookSource(bookSourceName: "Comic media", bookSourceUrl: "https://fixture.local",
                                bookSourceType: 2, ruleContent: SourceRule(fields: ["content": "#content@html"]))
        let playlist = "#EXTM3U\r\n#EXT-X-TARGETDURATION:8\r\n#EXTINF:8.0,\r\n/segment.ts"
        for (path, mime) in [("/chapter", "Application/Vnd.Apple.MpegURL; charset=utf-8"),
                             ("/chapter.m3u8", "text/plain")] {
            let url = bookURL + path
            let chapter = BookChapter(title: "Mixed media", url: url, bookUrl: bookURL, index: 0)
            let network = Stage18FixtureNetwork(responses: [url: .init(body: playlist, contentType: mime)])
            let result = await LegadoSourceEngine(network: network).getContent(source: source, chapter: chapter)
            guard case .failure(let error) = result, case .unsupported = error else {
                XCTFail("A confirmed streaming playlist is not an empty or readable comic chapter: \(result)")
                continue
            }
            XCTAssertEqual(SourceDiagnosticClassifier.kind(error: error, stage: "content"), .unsupported)
            XCTAssertEqual(network.requestedURLs, [url], "Comic reading must not follow a streaming playlist")
        }
    }

    func testComicImageRulesStillRunWithAnIncorrectPlaylistContentType() async throws {
        let url = "https://fixture.local/comic/chapter"
        let source = BookSource(bookSourceName: "Comic media", bookSourceUrl: "https://fixture.local",
                                bookSourceType: 2, ruleContent: SourceRule(fields: ["content": "#content@html"]))
        let chapter = BookChapter(title: "Pictures", url: url, bookUrl: "https://fixture.local/comic", index: 0)
        let mislabeled = Stage18FixtureNetwork.Payload(
            body: "<html><body><div id='content'><img src='/img/01.webp'></div></body></html>",
            contentType: "application/vnd.apple.mpegurl")
        let network = Stage18FixtureNetwork(responses: [url: mislabeled])
        let result = try await LegadoSourceEngine(network: network).getContent(source: source, chapter: chapter).get()
        XCTAssertEqual(ComicChapterResources(content: result).pages.map(\.url), ["https://fixture.local/img/01.webp"])
    }

    func testTOCPaginationStopsAtThirtyPages() async throws {
        let source = paginationSource()
        var responses: [String: Stage18FixtureNetwork.Payload] = [:]
        for page in 1...31 {
            let url = "https://fixture.local/toc/\(page)"
            let next = page < 31 ? "<a class='next' href='/toc/\(page + 1)'>next</a>" : ""
            responses[url] = html("<div class='chapter'><a href='/chapter/\(page)'>\(page)</a></div>\(next)")
        }
        let network = Stage18FixtureNetwork(responses: responses)
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let detail = BookDetail(name: "Paged", author: nil, coverUrl: nil, bookUrl: "https://fixture.local/book", tocUrl: "https://fixture.local/toc/1", sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)

        let result = await engine.getChapterList(source: source, book: detail)
        guard case .success(let chapters) = result else { return XCTFail("expected chapters: \(result)") }
        XCTAssertEqual(chapters.count, 30)
        XCTAssertEqual(network.requests.count, 30)
        XCTAssertFalse(network.requestedURLs.contains("https://fixture.local/toc/31"))
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "toc.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "max-pages")
        XCTAssertEqual(stop.details["pagesLoaded"], "30")
        XCTAssertEqual(stop.details["maxPages"], "30")
    }

    func testContentPaginationStopsOnDuplicateAndRetainsSuccessfulParagraphs() async throws {
        let source = paginationSource()
        let first = "https://fixture.local/content/1"
        let second = "https://fixture.local/content/2"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div id='content'>页一</div><a class='next' href='/content/2'>next</a>"),
            second: html("<div id='content'>页二</div><a class='next' href='/content/2'>next</a>")
        ])
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let chapter = BookChapter(title: "Chapter", url: first, bookUrl: "https://fixture.local/book", index: 0, isVip: false)

        let result = await engine.getContent(source: source, chapter: chapter)
        guard case .success(let content) = result else { return XCTFail("expected content: \(result)") }
        XCTAssertEqual(content.paragraphs, ["页一", "页二"])
        XCTAssertNil(content.nextContentUrl)
        XCTAssertEqual(network.requestedURLs, [first, second])
        let stop = try XCTUnwrap(diagnostics.events.first { $0.stage == "content.pagination.stop" })
        XCTAssertEqual(stop.details["reason"], "duplicate-url")
        XCTAssertEqual(stop.details["pagesLoaded"], "2")
    }

    func testContentPaginationOnlyDeduplicatesAtThePageBoundary() async throws {
        let source = paginationSource(contentRule: "#content@html")
        let first = "https://fixture.local/content/1"
        let second = "https://fixture.local/content/2"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div id='content'><p>正文起始</p><p>横跨网页的重叠段落</p><p>（本章未完，请翻页）</p></div><a class='next' href='/content/2'>next</a>"),
            second: html("<div id='content'><p>横跨网页的重叠段落</p><p>他说：再等一等。</p><p>他说：再等一等。</p><p>她低声说：“本章未完，请翻页。”</p></div>")
        ])
        let engine = LegadoSourceEngine(network: network)
        let chapter = BookChapter(title: "Chapter", url: first, bookUrl: "https://fixture.local/book", index: 0, isVip: false)

        let content = try await engine.getContent(source: source, chapter: chapter).get()
        XCTAssertEqual(content.paragraphs, ["正文起始", "横跨网页的重叠段落", "他说：再等一等。", "他说：再等一等。", "她低声说：“本章未完，请翻页。”"])
        XCTAssertNil(content.nextContentUrl)
        XCTAssertEqual(network.requestedURLs, [first, second])
    }

    func testUnfulfilledContentPaginationKeepsItsUnfinishedMarker() async throws {
        let source = paginationSource(contentRule: "#content@html")
        let first = "https://fixture.local/content/1"
        let second = "https://fixture.local/content/2"
        let network = Stage18FixtureNetwork(responses: [
            first: html("<div id='content'><p>目前只抓到这一段</p><p>（本章未完，请翻页）</p></div><a class='next' href='/content/2'>next</a>")
        ])
        let engine = LegadoSourceEngine(network: network)
        let chapter = BookChapter(title: "Chapter", url: first, bookUrl: "https://fixture.local/book", index: 0, isVip: false)

        let content = try await engine.getContent(source: source, chapter: chapter).get()
        XCTAssertEqual(content.paragraphs, ["目前只抓到这一段", "（本章未完，请翻页）"])
        XCTAssertEqual(content.nextContentUrl, second)
    }

    func testSourcePromotionMatchesOnlyObservedStandaloneSignatureAndHost() async throws {
        let footer = "喜 欢 剑 来 请 大 家 收 藏：(www.ymxshuwu.com)剑来衍墨轩书屋更新速度全网最快。"
        let dialogue = "她指着纸条说：“喜欢剑来请大家收藏。”"
        let chapterHTML = html("<div id='content'><p>正文段落</p><p>\(footer)</p><p>\(dialogue)</p></div>")
        let source = paginationSource(contentRule: "#content@html")
        let hosts = ["www.ymxshuwu.com", "fixture.local"]
        for host in hosts {
            let url = "https://\(host)/content/1"
            let network = Stage18FixtureNetwork(responses: [url: chapterHTML])
            let engine = LegadoSourceEngine(network: network)
            let chapter = BookChapter(title: "Chapter", url: url, bookUrl: url, index: 0, isVip: false)
            let content = try await engine.getContent(source: source, chapter: chapter).get()
            let expected = host == hosts[0] ? ["正文段落", dialogue] : ["正文段落", footer, dialogue]
            XCTAssertEqual(content.paragraphs, expected)
        }
    }

    func testContentPaginationFollowsNinePages() async throws {
        let source = paginationSource()
        var responses: [String: Stage18FixtureNetwork.Payload] = [:]
        for page in 1...9 {
            let url = "https://fixture.local/content/\(page)"
            let next = page < 9 ? "<a class='next' href='/content/\(page + 1)'>next</a>" : ""
            responses[url] = html("<div id='content'>页\(page)</div>\(next)")
        }
        let network = Stage18FixtureNetwork(responses: responses)
        let diagnostics = Stage18Diagnostics()
        let engine = LegadoSourceEngine(network: network, diagnostics: DiagnosticSink { event in diagnostics.append(event) })
        let chapter = BookChapter(title: "Chapter", url: "https://fixture.local/content/1", bookUrl: "https://fixture.local/book", index: 0, isVip: false)

        let result = await engine.getContent(source: source, chapter: chapter)
        guard case .success(let content) = result else { return XCTFail("expected content: \(result)") }
        // Long serialised chapters used to stop after eight pages mid-sentence.
        // The safety cap is now 24, so this nine-page chapter must finish.
        XCTAssertEqual(content.paragraphs, (1...9).map { "页\($0)" })
        XCTAssertNil(content.nextContentUrl)
        XCTAssertEqual(network.requests.count, 9)
        XCTAssertTrue(network.requestedURLs.contains("https://fixture.local/content/9"))
    }

    func testWholeBookDirectoryRejectsAPrefixAndCanRetryWhenTheLastPageReturns() async throws {
        let source = paginationSource()
        let book = BookDetail(name: "Fixture", author: nil, coverUrl: nil, bookUrl: "https://fixture.local/book",
                              tocUrl: "https://fixture.local/toc/1", sourceName: source.bookSourceName,
                              sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
        let first = "https://fixture.local/toc/1", second = "https://fixture.local/toc/2"
        let firstHTML = html("<div class='chapter'><a href='/c/1'>第一话</a></div><a class='next' href='/toc/2'>next</a>")
        let unavailable = LegadoSourceEngine(network: Stage18FixtureNetwork(responses: [first: firstHTML],
            failures: [second: .network("fixture second page unavailable")]))
        let readable = try await unavailable.getChapterList(source: source, book: book).get()
        XCTAssertEqual(readable.map(\.title), ["第一话"], "The ordinary reader may still open the available prefix")
        let strict = await unavailable.getCompleteChapterList(source: source, book: book)
        guard case .failure = strict else { return XCTFail("A readable prefix must never become a whole-book download") }

        let recovered = LegadoSourceEngine(network: Stage18FixtureNetwork(responses: [first: firstHTML,
            second: html("<div class='chapter'><a href='/c/2'>第二话</a></div>")]))
        let complete = try await recovered.getCompleteChapterList(source: source, book: book).get()
        XCTAssertEqual(complete.map(\.title), ["第一话", "第二话"])
        XCTAssertEqual(complete.map(\.index), [0, 1])
    }

    func testWholeBookDirectoryRejectsLoopsRatherThanReportingFalseCompletion() async {
        let source = paginationSource()
        let first = "https://fixture.local/toc/1"
        let book = BookDetail(name: "Fixture", author: nil, coverUrl: nil, bookUrl: first, tocUrl: first,
                              sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
        let network = Stage18FixtureNetwork(responses: [first:
            html("<div class='chapter'><a href='/c/1'>第一话</a></div><a class='next' href='/toc/1'>next</a>")])
        let engine = LegadoSourceEngine(network: network)
        let result = await engine.getCompleteChapterList(source: source, book: book)
        guard case .failure = result else { return XCTFail("A repeated next URL is not a verified directory end") }
        XCTAssertEqual(network.requestedURLs, [first])
    }

    func testWholeBookDirectoryDoesNotCountThePaginationSafetyCapAsCompletion() async {
        let source = paginationSource()
        let first = "https://fixture.local/toc/1"
        let book = BookDetail(name: "Fixture", author: nil, coverUrl: nil, bookUrl: first, tocUrl: first,
                              sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil, latestChapter: nil)
        let responses = Dictionary(uniqueKeysWithValues: (1...30).map { page in
            ("https://fixture.local/toc/\(page)", html("<div class='chapter'><a href='/c/\(page)'>第\(page)话</a></div><a class='next' href='/toc/\(page + 1)'>next</a>"))
        })
        let network = Stage18FixtureNetwork(responses: responses)
        let engine = LegadoSourceEngine(network: network)
        let result = await engine.getCompleteChapterList(source: source, book: book)
        guard case .failure(let error) = result else { return XCTFail("A capped directory must not be called complete") }
        XCTAssertTrue(error.displayMessage.contains("30 页"))
        XCTAssertEqual(network.requestedURLs.count, 30)
        XCTAssertFalse(network.requestedURLs.contains("https://fixture.local/toc/31"))
    }

    private func paginationSource(contentRule: String = "#content@text") -> BookSource {
        BookSource(
            bookSourceName: "Stage18 pagination",
            bookSourceUrl: "https://fixture.local",
            ruleToc: SourceRule(fields: ["chapterList": ".chapter", "chapterName": "a@text", "chapterUrl": "a@href", "nextTocUrl": "a.next@href"]),
            ruleContent: SourceRule(fields: ["content": contentRule, "nextContentUrl": "a.next@href"])
        )
    }

    private func html(_ body: String) -> Stage18FixtureNetwork.Payload {
        .init(body: "<html><body>\(body)</body></html>")
    }
}

private final class Stage18FixtureNetwork: SourceNetworkClient, @unchecked Sendable {
    struct Payload: Sendable {
        let body: String
        let contentType: String
        init(body: String, contentType: String = "text/html") {
            self.body = body
            self.contentType = contentType
        }
    }

    private let responses: [String: Payload]
    private let failures: [String: SourceEngineError]
    private let lock = NSLock()
    private var recorded: [SourceRequest] = []

    init(responses: [String: Payload], failures: [String: SourceEngineError] = [:]) {
        self.responses = responses
        self.failures = failures
    }

    var requests: [SourceRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var requestedURLs: [String] { requests.map(\.url.absoluteString) }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lock.lock(); recorded.append(request); lock.unlock()
        if let failure = failures[request.url.absoluteString] { return .failure(failure) }
        guard let payload = responses[request.url.absoluteString] else {
            return .failure(.network("fixture missing: \(request.url.absoluteString)"))
        }
        return .success(SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: ["Content-Type": payload.contentType],
            body: payload.body,
            data: Data(payload.body.utf8)
        ))
    }
}

private final class Stage18Diagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [DiagnosticEvent] = []

    var events: [DiagnosticEvent] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func append(_ event: DiagnosticEvent) {
        lock.lock(); stored.append(event); lock.unlock()
    }
}
