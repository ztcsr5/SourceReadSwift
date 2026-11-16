import Foundation
import XCTest
@testable import SourceReadSwift

@MainActor
final class SourceImageRequestHeadersTests: XCTestCase {
    private let sourceURL = "https://image-headers.fixture.invalid"
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII=")!

    func testResolverForwardsTheSourceAndChapterToProvider() async throws {
        let engine = ImageHeaderFixtureEngine(headers: .success(["X-Session": "synthetic-session"]))
        let source = makeSource()
        let chapter = makeChapter()
        let headers = try await SourceImageRequestHeaders.resolve(engine: engine, source: source, chapter: chapter).get()
        XCTAssertEqual(headers, ["X-Session": "synthetic-session"])
        let calls = await engine.headerCalls
        XCTAssertEqual(calls.map(\.sourceURL), [source.bookSourceUrl])
        XCTAssertEqual(calls.map(\.chapterURL), [chapter.url])
    }

    func testNonProviderEngineRetainsStaticImageHeaderDefaults() async throws {
        let source = makeSource(header: #"{"X-Static":"synthetic-static"}"#)
        let chapter = makeChapter()
        let headers = try await SourceImageRequestHeaders.resolve(engine: StaticImageHeaderEngine(), source: source, chapter: chapter).get()
        XCTAssertEqual(headers["X-Static"], "synthetic-static")
        XCTAssertEqual(headers["Referer"], chapter.url)
        XCTAssertFalse(headers["User-Agent", default: ""].isEmpty)
        XCTAssertTrue(headers["Accept", default: ""].contains("image/"))
    }

    func testLegadoImageHeadersUseLibraryCacheLoginAndLoginHeaderPrecedenceWithoutDecodeRule() async throws {
        let source = makeSource(header: "@js: JSON.stringify(imageHeaders());", library: """
        function imageHeaders() {
          java.put('imageHeaderCalls', Number(java.get('imageHeaderCalls') || 0) + 1);
          return {'X-Device':cache.get('device'), 'X-Form':source.getLoginInfoMap().get('account'),
            'Authorization':'source-value', 'X-Chapter':baseUrl};
        }
        """)
        let chapter = makeChapter()
        let cache = SourceScriptCacheStore(isPersistent: false)
        try cache.put("synthetic-device", for: "device", scope: source.bookSourceUrl)
        let engine = LegadoSourceEngine(cookieStore: SourceCookieStore(storageURL: nil), scriptCacheStore: cache)
        let state = engine.persistentState(for: source)
        state.put("synthetic-account", for: "source.login.account")
        state.put(#"{"authorization":"synthetic-login-header","X-Login":"session"}"#, for: "source.loginHeader")
        state.put("specific-login-field", for: "source.loginHeader.x-login")
        let resources = ComicChapterResources(offlinePages: [ComicPage(id: 0, url: "https://cdn.fixture.invalid/page.png")])
        let requests = try await ComicChapterRequestBuilder.build(resources: resources, source: source, chapter: chapter, engine: engine).get()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["X-Device"], "synthetic-device")
        XCTAssertEqual(request.headers["X-Form"], "synthetic-account")
        XCTAssertEqual(request.headers["X-Chapter"], chapter.url)
        XCTAssertEqual(request.headers["authorization"], "synthetic-login-header")
        XCTAssertEqual(request.headers["x-login"], "specific-login-field")
        XCTAssertEqual(request.headers.keys.filter { $0.lowercased() == "authorization" }.count, 1)
        XCTAssertEqual(request.headers["Referer"], chapter.url)
        XCTAssertNil(request.decodeContext)
        XCTAssertEqual(state.get("imageHeaderCalls"), "1")
    }

    func testChapterResolvesHeadersOnceAndPageOverridesWinCaseInsensitively() async throws {
        let engine = ImageHeaderFixtureEngine(headers: .success(["Authorization": "chapter-session", "X-Shared": "shared"]))
        let resources = ComicChapterResources(offlinePages: [
            ComicPage(id: 0, url: "https://cdn.fixture.invalid/one.png", headers: ["authorization": "page-session", "referer": "https://page.fixture.invalid"]),
            ComicPage(id: 1, url: "https://cdn.fixture.invalid/two.png"),
            ComicPage(id: 2, url: "file:///synthetic/offline.png", headers: ["Authorization": "discard-local"]),
            ComicPage(id: 3, url: inlineURL, headers: ["Authorization": "discard-inline"])
        ])
        let chapter = makeChapter()
        let requests = try await ComicChapterRequestBuilder.build(resources: resources, source: makeSource(), chapter: chapter, engine: engine).get()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests[0].headers["authorization"], "page-session")
        XCTAssertEqual(requests[0].headers["referer"], "https://page.fixture.invalid")
        XCTAssertEqual(requests[0].headers.keys.filter { $0.lowercased() == "authorization" }.count, 1)
        XCTAssertEqual(requests[0].headers.keys.filter { $0.lowercased() == "referer" }.count, 1)
        XCTAssertEqual(requests[1].headers["Authorization"], "chapter-session")
        XCTAssertEqual(requests[1].headers["X-Shared"], "shared")
        XCTAssertEqual(requests[1].headers["Referer"], chapter.url)
        XCTAssertTrue(requests[2].headers.isEmpty)
        XCTAssertTrue(requests[3].headers.isEmpty)
        let calls = await engine.headerCalls
        XCTAssertEqual(calls.count, 1)
        let cookieLookups = await engine.cookieLookups
        XCTAssertEqual(cookieLookups, ["https://cdn.fixture.invalid/one.png", "https://cdn.fixture.invalid/two.png"])
    }

    func testImageCookiesMatchEachActualHostPathAndSecureScheme() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let origin = try XCTUnwrap(URL(string: sourceURL + "/protected/login"))
        await cookies.storeSetCookieHeaders(["Set-Cookie": "reader=host-only; Path=/protected; Secure"], for: origin)
        let shared = try XCTUnwrap(HTTPCookie(properties: [
            .name: "images", .value: "shared-domain", .domain: ".images.fixture.invalid", .path: "/pages", .secure: "TRUE"
        ]))
        await cookies.storeWebViewCookies([shared])
        let engine = LegadoSourceEngine(cookieStore: cookies, scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        let addresses = [
            sourceURL + "/protected/one.png",
            sourceURL + "/protectedness/two.png",
            "https://sibling.image-headers.fixture.invalid/protected/three.png",
            "https://cdn.images.fixture.invalid/pages/four.png",
            "https://other.invalid/pages/five.png",
            "http://image-headers.fixture.invalid/protected/six.png",
            "https://notimages.fixture.invalid/pages/seven.png"
        ]
        let resources = ComicChapterResources(offlinePages: addresses.enumerated().map { ComicPage(id: $0.offset, url: $0.element) })
        let requests = try await ComicChapterRequestBuilder.build(resources: resources, source: makeSource(), chapter: makeChapter(), engine: engine).get()
        XCTAssertEqual(requests.map(\.url), addresses)
        XCTAssertEqual(requests.map { cookieHeader($0) }, ["reader=host-only", nil, nil, "images=shared-domain", nil, nil, nil])
    }

    func testExplicitSourcePageAndEmptyCookiesOverrideTheAutomaticJar() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=automatic; Path=/"], for: try XCTUnwrap(URL(string: sourceURL)))
        let engine = LegadoSourceEngine(cookieStore: cookies, scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        let source = makeSource(header: #"{"cOoKiE":"source=explicit"}"#)
        let resources = ComicChapterResources(offlinePages: [
            ComicPage(id: 0, url: sourceURL + "/one.png", headers: ["COOKIE": "page=explicit"]),
            ComicPage(id: 1, url: sourceURL + "/two.png"),
            ComicPage(id: 2, url: sourceURL + "/three.png", headers: ["cookie": ""])
        ])
        let requests = try await ComicChapterRequestBuilder.build(resources: resources, source: source, chapter: makeChapter(), engine: engine).get()
        XCTAssertEqual(requests.map { cookieHeader($0) }, ["page=explicit", "source=explicit", ""])
        XCTAssertTrue(requests.allSatisfy { $0.headers.keys.filter { $0.lowercased() == "cookie" }.count == 1 })
    }

    func testDeletedAndLoggedOutCookiesDoNotReturnFromOldSourceSnapshots() async throws {
        let cookies = SourceCookieStore(storageURL: nil)
        let source = makeSource()
        let origin = try XCTUnwrap(URL(string: sourceURL))
        let engine = LegadoSourceEngine(cookieStore: cookies, scriptCacheStore: SourceScriptCacheStore(isPersistent: false))
        engine.persistentState(for: source).put("session=stale-snapshot", for: "cookieHeader")
        let resources = ComicChapterResources(offlinePages: [ComicPage(id: 0, url: sourceURL + "/page.png")])
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=first; Path=/"], for: origin)
        let first = try await ComicChapterRequestBuilder.build(resources: resources, source: source, chapter: makeChapter(), engine: engine).get()
        XCTAssertEqual(cookieHeader(try XCTUnwrap(first.first)), "session=first")
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=; Path=/; Max-Age=0"], for: origin)
        let deleted = try await ComicChapterRequestBuilder.build(resources: resources, source: source, chapter: makeChapter(), engine: engine).get()
        XCTAssertNil(cookieHeader(try XCTUnwrap(deleted.first)))
        await cookies.storeSetCookieHeaders(["Set-Cookie": "session=second; Path=/"], for: origin)
        let signedIn = try await ComicChapterRequestBuilder.build(resources: resources, source: source, chapter: makeChapter(), engine: engine).get()
        XCTAssertEqual(cookieHeader(try XCTUnwrap(signedIn.first)), "session=second")
        _ = try await engine.performLoginAction(source: source,
            action: "cookie.removeCookie(source.bookSourceUrl); source.removeLoginInfo();", credentials: [:]).get()
        let loggedOut = try await ComicChapterRequestBuilder.build(resources: resources, source: source, chapter: makeChapter(), engine: engine).get()
        XCTAssertNil(cookieHeader(try XCTUnwrap(loggedOut.first)))
        let cleared = await cookies.cookieHeader(for: origin)
        XCTAssertNil(cleared)
    }

    func testLocalInlineAndEmptyChaptersNeverEvaluateNetworkHeaders() async throws {
        let engine = ImageHeaderFixtureEngine(headers: .failure(.rule("Header must not run for local pages")))
        for pages in [[], [ComicPage(id: 0, url: "file:///synthetic/offline.png"), ComicPage(id: 1, url: inlineURL)]] {
            let resources = ComicChapterResources(offlinePages: pages)
            let requests = try await ComicChapterRequestBuilder.build(resources: resources, source: makeSource(), chapter: makeChapter(), engine: engine).get()
            XCTAssertEqual(requests.map(\.url), pages.map(\.url))
            XCTAssertTrue(requests.allSatisfy { $0.headers.isEmpty && $0.decodeContext == nil })
        }
        for address in ["file:///synthetic/offline.png", inlineURL, "ftp://fixture.invalid/page.png", "relative/page.png"] {
            let request = ComicImageRequest(url: address, headers: [:])
            let resolved = await SourceImageRequestHeaders.addingSessionCookies(to: request, engine: engine)
            XCTAssertTrue(resolved.headers.isEmpty)
        }
        let calls = await engine.headerCalls
        XCTAssertTrue(calls.isEmpty)
        let cookieLookups = await engine.cookieLookups
        XCTAssertTrue(cookieLookups.isEmpty)
    }

    func testProviderFailureDoesNotFallBackToStaticHeadersOrProduceRequests() async {
        let engine = ImageHeaderFixtureEngine(headers: .failure(.rule("Synthetic header failure")))
        let source = makeSource(header: #"{"X-Static":"must-not-be-used"}"#)
        let resolved = await SourceImageRequestHeaders.resolve(engine: engine, source: source, chapter: makeChapter())
        guard case .failure = resolved else { return XCTFail("Provider failure silently became static headers") }
        let resources = ComicChapterResources(offlinePages: [ComicPage(id: 0, url: "https://cdn.fixture.invalid/page.png")])
        let requests = await ComicChapterRequestBuilder.build(resources: resources, source: source, chapter: makeChapter(), engine: engine)
        guard case .failure = requests else { return XCTFail("Failed headers produced image requests") }
    }

    func testDownloadHeaderFailureFetchesNoPagesAndCommitsNoArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root))
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let archive = ComicOfflineArchive(directory: root.appendingPathComponent("comics"))
        let fetches = ImageHeaderPageFetches(bytes: png)
        let engine = ImageHeaderFixtureEngine(headers: .failure(.rule("Synthetic header failure")))
        let coordinator = ChapterDownloadCoordinator(store: store, comicArchive: archive, fetchComicPage: { await fetches.fetch($0) })
        defer { coordinator.cancelAll() }
        let source = makeSource()
        let chapter = makeChapter()
        coordinator.start(bookID: "comic", source: source, title: "Comic", chapters: [chapter], engine: engine, cacheStore: cache, purifyRules: [])
        try await waitForDownload(coordinator)
        let record = try XCTUnwrap(store.record(bookID: "comic"))
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.failedIndexes, [chapter.index])
        XCTAssertTrue(record.completedIndexes.isEmpty)
        let requests = await fetches.requests
        XCTAssertTrue(requests.isEmpty)
        let pages = await archive.pages(sourceURL: source.bookSourceUrl, chapter: chapter)
        let hasManifest = await archive.hasManifest(sourceURL: source.bookSourceUrl, chapter: chapter)
        XCTAssertNil(pages)
        XCTAssertFalse(hasManifest)
        let calls = await engine.headerCalls
        XCTAssertEqual(calls.count, 1)
    }

    func testDownloadSendsDynamicAndPerPageHeadersThenReopensCompleteArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root))
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let archiveURL = root.appendingPathComponent("comics")
        let archive = ComicOfflineArchive(directory: archiveURL)
        let fetches = ImageHeaderPageFetches(bytes: png)
        let engine = ImageHeaderFixtureEngine(headers: .success(["Authorization": "chapter-session", "X-Shared": "shared"]))
        let coordinator = ChapterDownloadCoordinator(store: store, comicArchive: archive, fetchComicPage: { await fetches.fetch($0) })
        defer { coordinator.cancelAll() }
        let source = makeSource()
        let chapter = makeChapter()
        coordinator.start(bookID: "comic", source: source, title: "Comic", chapters: [chapter], engine: engine, cacheStore: cache, purifyRules: [])
        try await waitForDownload(coordinator)
        let record = try XCTUnwrap(store.record(bookID: "comic"))
        XCTAssertEqual(record.status, .completed)
        XCTAssertEqual(record.completedIndexes, [chapter.index])
        XCTAssertTrue(record.failedIndexes.isEmpty)
        let requests = await fetches.requests
        XCTAssertEqual(requests.map(\.url), ["https://cdn.fixture.invalid/one.png", "https://cdn.fixture.invalid/two.png"])
        XCTAssertEqual(requests.first?.headers["authorization"], "page-session")
        XCTAssertEqual(requests.first?.headers.keys.filter { $0.lowercased() == "authorization" }.count, 1)
        XCTAssertEqual(requests.last?.headers["Authorization"], "chapter-session")
        XCTAssertTrue(requests.allSatisfy { $0.headers["X-Shared"] == "shared" })
        let calls = await engine.headerCalls
        XCTAssertEqual(calls.count, 1)
        let reopened = ComicOfflineArchive(directory: archiveURL)
        let savedPages = await reopened.pages(sourceURL: source.bookSourceUrl, chapter: chapter)
        let pages = try XCTUnwrap(savedPages)
        XCTAssertEqual(pages.count, 2)
        for page in pages {
            let url = try XCTUnwrap(URL(string: page.url))
            XCTAssertTrue(url.isFileURL)
            XCTAssertEqual(try Data(contentsOf: url), png)
        }
    }

    func testDownloadOfOnlyInlinePagesSkipsFailingHeaderProvider() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root))
        let cache = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root))
        let archive = ComicOfflineArchive(directory: root.appendingPathComponent("comics"))
        let fetches = ImageHeaderPageFetches(bytes: png)
        let engine = ImageHeaderFixtureEngine(headers: .failure(.rule("Inline page does not need a session")), paragraphs: [inlineURL])
        let coordinator = ChapterDownloadCoordinator(store: store, comicArchive: archive, fetchComicPage: { await fetches.fetch($0) })
        defer { coordinator.cancelAll() }
        let source = makeSource()
        let chapter = makeChapter()
        coordinator.start(bookID: "comic", source: source, title: "Comic", chapters: [chapter], engine: engine, cacheStore: cache, purifyRules: [])
        try await waitForDownload(coordinator)
        XCTAssertEqual(store.record(bookID: "comic")?.status, .completed)
        let calls = await engine.headerCalls
        XCTAssertTrue(calls.isEmpty)
        let requests = await fetches.requests
        XCTAssertEqual(requests.map(\.url), [inlineURL])
        XCTAssertTrue(requests.allSatisfy { $0.headers.isEmpty })
        let saved = await archive.contains(sourceURL: source.bookSourceUrl, chapter: chapter)
        XCTAssertTrue(saved)
    }

    private var inlineURL: String { "srdata://inline/" + String(repeating: "a", count: 64) + ".png" }

    private func cookieHeader(_ request: ComicImageRequest) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare("Cookie") == .orderedSame }?.value
    }

    private func makeSource(header: String? = nil, library: String = "") -> BookSource {
        BookSource(bookSourceName: "Image header fixture", bookSourceUrl: sourceURL, bookSourceType: 2,
            header: header, raw: ["jsLib": library])
    }

    private func makeChapter() -> BookChapter {
        BookChapter(title: "Chapter 7", url: sourceURL + "/chapter/7", bookUrl: sourceURL + "/book", index: 7, isVip: false)
    }

    private func waitForDownload(_ coordinator: ChapterDownloadCoordinator) async throws {
        for _ in 0..<500 {
            if !coordinator.isRunning(bookID: "comic") { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw ImageHeaderFixtureFailure.downloadStillRunning
    }
}

private enum ImageHeaderFixtureFailure: Error { case downloadStillRunning }

private actor ImageHeaderFixtureEngine: SourceEngine, SourceImageRequestHeadersProviding {
    struct HeaderCall: Sendable { let sourceURL: String; let chapterURL: String }
    private let headers: Result<[String: String], SourceEngineError>
    private let paragraphs: [String]
    private(set) var headerCalls: [HeaderCall] = []
    private(set) var cookieLookups: [String] = []

    init(headers: Result<[String: String], SourceEngineError>, paragraphs: [String] = [
        #"[{"url":"https://cdn.fixture.invalid/one.png","headers":{"authorization":"page-session"}},{"url":"https://cdn.fixture.invalid/two.png"}]"#
    ]) {
        self.headers = headers
        self.paragraphs = paragraphs
    }

    func imageRequestHeaders(source: BookSource, chapter: BookChapter) async -> Result<[String: String], SourceEngineError> {
        headerCalls.append(HeaderCall(sourceURL: source.bookSourceUrl, chapterURL: chapter.url))
        return headers
    }
    func imageCookieHeader(for url: URL) async -> String? {
        cookieLookups.append(url.absoluteString)
        return nil
    }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs))
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Not used by image header fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}

private struct StaticImageHeaderEngine: SourceEngine {
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> { .failure(.rule("Not used by static image header fixture")) }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Not used by static image header fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}

private actor ImageHeaderPageFetches {
    private let bytes: Data
    private(set) var requests: [ComicImageRequest] = []
    init(bytes: Data) { self.bytes = bytes }
    func fetch(_ request: ComicImageRequest) -> Result<Data, ComicImageFailure> {
        requests.append(request)
        return .success(bytes)
    }
}
