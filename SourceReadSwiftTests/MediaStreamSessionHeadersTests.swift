import AVFoundation
import Foundation
import XCTest
@testable import SourceReadSwift

/// Local empty compositions prove request wiring, never HTTP/HLS playback.
@MainActor
final class MediaStreamSessionHeadersTests: XCTestCase {
    func testResolverUsesDynamicLibraryCacheLoginAndActualStreamCookies() async throws {
        let source = BookSource(bookSourceName: "Media header fixture", bookSourceUrl: "https://media.fixture.invalid",
            header: "@js: mediaHeaders()", raw: ["jsLib": """
            function mediaHeaders() { return {'X-Device':cache.get('device'),
              'X-Account':source.getLoginInfoMap().get('account'), 'Authorization':'source-token'}; }
            """])
        let cookies = SourceCookieStore(storageURL: nil)
        await cookies.storeSetCookieHeaders(["Set-Cookie": "stream=synthetic-session; Path=/protected; Secure"],
            for: try XCTUnwrap(URL(string: "https://cdn.fixture.invalid/protected/login")))
        await cookies.storeSetCookieHeaders(["Set-Cookie": "sourceOnly=must-not-leak; Path=/"],
            for: try XCTUnwrap(URL(string: source.bookSourceUrl)))
        let cache = SourceScriptCacheStore(isPersistent: false)
        try cache.put("synthetic-device", for: "device", scope: source.bookSourceUrl)
        let engine = LegadoSourceEngine(cookieStore: cookies, scriptCacheStore: cache)
        let state = engine.persistentState(for: source)
        state.put("synthetic-account", for: "source.login.account")
        state.put("login-token", for: "source.loginHeader.authorization")
        state.put("sourceOnly=stale-snapshot", for: "cookieHeader")
        let request = try await MediaStreamRequest.resolve("https://cdn.fixture.invalid/protected/episode.m3u8?sign=a%2Bb",
            source: source, episode: episode(), engine: engine).get()
        XCTAssertEqual(request.url.query, "sign=a%2Bb")
        XCTAssertEqual(request.headers["X-Device"], "synthetic-device")
        XCTAssertEqual(request.headers["X-Account"], "synthetic-account")
        XCTAssertEqual(request.headers["authorization"], "login-token")
        XCTAssertEqual(request.headers["Cookie"], "stream=synthetic-session")
        XCTAssertEqual(request.headers["Accept"], "*/*")
        let unrelated = try await MediaStreamRequest.resolve("https://unrelated.fixture.invalid/episode.mp3",
            source: source, episode: episode(), engine: engine).get()
        XCTAssertNil(unrelated.headers["Cookie"])
    }

    func testURLHeadersKeepFinalPriorityAndUnsafeFieldsAreFiltered() async throws {
        let engine = MediaHeaderFixtureEngine(headers: .success([
            "Authorization": "source-token", "accept": "image/*", "Cookie": "source-cookie", "Connection": "keep-alive"
        ]), cookie: "automatic-cookie")
        let reference = #"../episode.mp3,{"headers":{"authorization":"episode-token","ACCEPT":"audio/*","cOoKiE":"","Host":"wrong.invalid","Content-Length":"999","X-Bad":"line\r\nbreak"}}"#
        let request = try await MediaStreamRequest.resolve(reference, source: source(), episode: episode(), engine: engine).get()
        XCTAssertEqual(request.url.absoluteString, "https://media.fixture.invalid/episode.mp3")
        XCTAssertEqual(request.headers["authorization"], "episode-token")
        XCTAssertEqual(request.headers["ACCEPT"], "audio/*")
        XCTAssertEqual(request.headers["cOoKiE"], "")
        for field in ["authorization", "accept", "cookie"] {
            XCTAssertEqual(request.headers.keys.filter { $0.lowercased() == field }.count, 1)
        }
        for field in ["host", "content-length", "connection", "x-bad"] {
            XCTAssertFalse(request.headers.keys.contains { $0.lowercased() == field })
        }
        let cookieLookups = await engine.cookieLookups
        XCTAssertTrue(cookieLookups.isEmpty)
    }

    func testInvalidReferencesNeverExecuteSourceHeaders() async {
        let engine = MediaHeaderFixtureEngine()
        for reference in ["file:///private/episode.mp3", "javascript:alert(1)", "https://user:password@media.fixture.invalid/episode.mp3"] {
            let outcome = await MediaStreamRequest.resolve(reference, source: source(), episode: episode(), engine: engine)
            guard case .failure = outcome else { XCTFail("Invalid media reference reached session resolution"); continue }
        }
        let calls = await engine.headerCalls
        let cookieLookups = await engine.cookieLookups
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(cookieLookups.isEmpty)
    }

    func testDirectVideoPassesResolvedHeadersToItsPlayerFactory() async throws {
        let created = expectation(description: "video item configured")
        var requests: [MediaStreamRequest] = []
        let session = VideoPlaybackSession(makePlayerItem: { request in
            requests.append(request)
            created.fulfill()
            return AVPlayerItem(asset: AVMutableComposition())
        })
        defer { session.stop() }
        let engine = MediaHeaderFixtureEngine(headers: .success(["X-Session": "video-session"]), cookie: "stream=video")
        session.start(videoConfiguration(chapters: [episode(path: "/episode.mp4")], engine: engine))
        await fulfillment(of: [created], timeout: 5)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.headers["X-Session"], "video-session")
        XCTAssertEqual(request.headers["Cookie"], "stream=video")
        let contentCalls = await engine.contentCalls
        XCTAssertTrue(contentCalls.isEmpty)
    }

    func testResolvedAudioPassesHeadersToItsPlayerFactory() async throws {
        let created = expectation(description: "audio item configured")
        var requests: [MediaStreamRequest] = []
        let coordinator = AudioBookPlaybackCoordinator(makePlayerItem: { request in
            requests.append(request)
            created.fulfill()
            return AVPlayerItem(asset: AVMutableComposition())
        })
        defer { coordinator.stop() }
        let engine = MediaHeaderFixtureEngine(headers: .success(["X-Session": "audio-session"]), cookie: "stream=audio")
        coordinator.startBook(book: book(), source: source(), chapters: [episode()], engine: engine)
        await fulfillment(of: [created], timeout: 5)
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url.absoluteString, "https://cdn.fixture.invalid/episode.mp3")
        XCTAssertEqual(request.headers["X-Session"], "audio-session")
        XCTAssertEqual(request.headers["Cookie"], "stream=audio")
        let contentCalls = await engine.contentCalls
        XCTAssertEqual(contentCalls, [episode().url])
    }

    func testVideoHeaderFailureUsesPlayerErrorAndCreatesNoItem() async {
        let failure = SourceEngineError.rule("Synthetic media header failure")
        let engine = MediaHeaderFixtureEngine(headers: .failure(failure))
        var creations = 0
        let session = VideoPlaybackSession(makePlayerItem: { _ in
            creations += 1
            return AVPlayerItem(asset: AVMutableComposition())
        })
        defer { session.stop() }
        session.start(videoConfiguration(chapters: [episode(path: "/episode.mp4")], engine: engine))
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in session.errorMessage != nil }, object: nil)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertEqual(session.errorMessage, failure.displayMessage)
        XCTAssertFalse(session.isLoading)
        XCTAssertNil(session.player.currentItem)
        XCTAssertEqual(creations, 0)
    }

    func testAudioHeaderFailureUsesPlayerErrorAndCreatesNoItem() async {
        let failure = SourceEngineError.rule("Synthetic media header failure")
        let engine = MediaHeaderFixtureEngine(headers: .failure(failure))
        var creations = 0
        let coordinator = AudioBookPlaybackCoordinator(makePlayerItem: { _ in
            creations += 1
            return AVPlayerItem(asset: AVMutableComposition())
        })
        defer { coordinator.stop() }
        coordinator.startBook(book: book(), source: source(), chapters: [episode(path: "/episode.mp3")], engine: engine)
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in coordinator.errorMessage != nil }, object: nil)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertEqual(coordinator.errorMessage, "加载音频失败: \(failure.displayMessage)")
        XCTAssertFalse(coordinator.isLoading)
        XCTAssertFalse(coordinator.isPlaying)
        XCTAssertNil(coordinator.currentAudioURL)
        XCTAssertEqual(creations, 0)
    }

    func testNewVideoEpisodeRejectsTheOldHeadersLateCompletion() async {
        let firstRequested = expectation(description: "first headers requested")
        let secondRequested = expectation(description: "second headers requested")
        let installed = expectation(description: "current episode installed")
        let stale = expectation(description: "old episode must not install")
        stale.isInverted = true
        let chapters = [episode(path: "/first.mp4"), episode(path: "/second.mp4", index: 1)]
        let engine = MediaHeaderFixtureEngine(holdsHeaders: true, onHeaders: { address in
            if address.hasSuffix("first.mp4") { firstRequested.fulfill() } else { secondRequested.fulfill() }
        })
        var requests: [MediaStreamRequest] = []
        let session = VideoPlaybackSession(makePlayerItem: { request in
            requests.append(request)
            if request.url.path.hasSuffix("first.mp4") { stale.fulfill() } else { installed.fulfill() }
            return AVPlayerItem(asset: AVMutableComposition())
        })
        defer { session.stop() }
        session.start(videoConfiguration(chapters: chapters, engine: engine))
        await fulfillment(of: [firstRequested], timeout: 5)
        session.playEpisode(at: 1)
        await fulfillment(of: [secondRequested], timeout: 5)
        await engine.releaseHeaders(for: chapters[0].url)
        await engine.releaseHeaders(for: chapters[1].url)
        await fulfillment(of: [installed, stale], timeout: 1)
        XCTAssertEqual(requests.map { $0.url.absoluteString }, [chapters[1].url])
        XCTAssertEqual(session.episodeOffset, 1)
    }

    func testStoppedAudioRejectsUncancellableHeadersWithoutStartingHTTPPlayback() async {
        let outcomes: [Result<[String: String], SourceEngineError>] = [
            .success(["X-Session": "stale-session"]), .failure(.rule("Stale audio header failure"))
        ]
        for outcome in outcomes {
            let requested = expectation(description: "audio headers requested")
            let stale = expectation(description: "stopped audio must not create a player")
            stale.isInverted = true
            let engine = MediaHeaderFixtureEngine(headers: outcome, holdsHeaders: true, onHeaders: { _ in requested.fulfill() })
            let coordinator = AudioBookPlaybackCoordinator(makePlayerItem: { _ in
                stale.fulfill()
                return AVPlayerItem(asset: AVMutableComposition())
            })
            defer { coordinator.stop() }
            let chapter = episode(path: "/episode.mp3")
            coordinator.startBook(book: book(), source: source(), chapters: [chapter], engine: engine)
            await fulfillment(of: [requested], timeout: 5)
            coordinator.stop()
            await engine.releaseHeaders(for: chapter.url)
            await fulfillment(of: [stale], timeout: 0.3)
            XCTAssertFalse(coordinator.isLoading)
            XCTAssertFalse(coordinator.isPlaying)
            XCTAssertNil(coordinator.currentAudioURL)
            XCTAssertNil(coordinator.currentBook)
            XCTAssertNil(coordinator.errorMessage)
        }
    }

    func testStoppedVideoRejectsUncancellableHeaderSuccessAndFailure() async {
        let outcomes: [Result<[String: String], SourceEngineError>] = [
            .success(["X-Session": "stale-session"]), .failure(.rule("Stale video header failure"))
        ]
        for outcome in outcomes {
            let requested = expectation(description: "video headers requested")
            let stale = expectation(description: "stopped video must not create an item")
            stale.isInverted = true
            let engine = MediaHeaderFixtureEngine(headers: outcome, holdsHeaders: true, onHeaders: { _ in requested.fulfill() })
            let session = VideoPlaybackSession(makePlayerItem: { _ in
                stale.fulfill()
                return AVPlayerItem(asset: AVMutableComposition())
            })
            defer { session.stop() }
            let chapter = episode(path: "/episode.mp4")
            session.start(videoConfiguration(chapters: [chapter], engine: engine))
            await fulfillment(of: [requested], timeout: 5)
            session.stop()
            await engine.releaseHeaders(for: chapter.url)
            await fulfillment(of: [stale], timeout: 0.3)
            XCTAssertFalse(session.isLoading)
            XCTAssertNil(session.player.currentItem)
            XCTAssertNil(session.errorMessage)
        }
    }

    private func source() -> BookSource {
        BookSource(bookSourceName: "Media session fixture", bookSourceUrl: "https://media.fixture.invalid")
    }

    private func episode(path: String = "/watch/episode", index: Int = 0) -> BookChapter {
        BookChapter(title: "Episode \(index)", url: "https://media.fixture.invalid" + path,
            bookUrl: "https://media.fixture.invalid/book", index: index)
    }

    private func book() -> SearchBook {
        SearchBook(name: "Audio fixture", author: nil, coverUrl: nil, bookUrl: "https://media.fixture.invalid/book",
            sourceName: source().bookSourceName, sourceUrl: source().bookSourceUrl)
    }

    private func videoConfiguration(chapters: [BookChapter], engine: SourceEngine) -> VideoPlaybackSession.Configuration {
        .init(bookID: nil, title: "Video fixture", source: source(), chapters: chapters, initialChapterIndex: 0,
            initialPositionSeconds: nil, engine: engine, bookshelf: nil)
    }
}

private actor MediaHeaderFixtureEngine: SourceEngine, SourceImageRequestHeadersProviding {
    private let headers: Result<[String: String], SourceEngineError>
    private let cookie: String?
    private let holdsHeaders: Bool
    private let onHeaders: @Sendable (String) -> Void
    private var pending: [String: CheckedContinuation<Result<[String: String], SourceEngineError>, Never>] = [:]
    private(set) var headerCalls: [String] = []
    private(set) var cookieLookups: [String] = []
    private(set) var contentCalls: [String] = []

    init(headers: Result<[String: String], SourceEngineError> = .success([:]), cookie: String? = nil,
         holdsHeaders: Bool = false, onHeaders: @escaping @Sendable (String) -> Void = { _ in }) {
        self.headers = headers
        self.cookie = cookie
        self.holdsHeaders = holdsHeaders
        self.onHeaders = onHeaders
    }

    func imageRequestHeaders(source: BookSource, chapter: BookChapter) async -> Result<[String: String], SourceEngineError> {
        headerCalls.append(chapter.url)
        if holdsHeaders {
            return await withCheckedContinuation { pending[chapter.url] = $0; onHeaders(chapter.url) }
        }
        onHeaders(chapter.url)
        return headers
    }
    func imageCookieHeader(for url: URL) async -> String? {
        cookieLookups.append(url.absoluteString)
        return cookie
    }
    func releaseHeaders(for address: String) {
        pending.removeValue(forKey: address)?.resume(returning: headers)
    }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        contentCalls.append(chapter.url)
        return .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: ["https://cdn.fixture.invalid/episode.mp3"]))
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Unused media header fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}
