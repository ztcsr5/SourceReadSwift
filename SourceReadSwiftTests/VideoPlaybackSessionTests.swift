import AVFoundation
import AVKit
import MediaPlayer
import SwiftUI
import XCTest
@testable import SourceReadSwift

@MainActor
final class VideoPlaybackSessionTests: XCTestCase {
    func testRealVideoResumesAfterDurationArrivesAndOldEndCannotAdvanceNewEpisode() async throws {
        let fixture = try XCTUnwrap(TestFixtureSupport.url(name: "episode", extension: "mp4", subdirectory: "media-playback"))
        let session = VideoPlaybackSession(makePlayerItem: { _ in AVPlayerItem(url: fixture) })
        defer { session.stop() }
        let chapters = episodes(hasDirectStreams: true)
        session.start(configuration(chapters: chapters, engine: HeldVideoEngine(), resume: 12))
        XCTAssertEqual(session.currentEpisode?.index, 8, "Persisted chapter IDs are not array offsets")
        let resumed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            session.duration > 20 && session.currentTime >= 12 && session.currentTime < 18
        }, object: nil)
        await fulfillment(of: [resumed], timeout: 15)
        XCTAssertGreaterThanOrEqual(session.player.currentTime().seconds, 12)
        session.pause()
        XCTAssertEqual(session.player.rate, 0)
        session.seek(to: 18)
        let sought = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(session.currentTime - 18) < 0.1 && abs(session.player.currentTime().seconds - 18) < 0.1
        }, object: nil)
        await fulfillment(of: [sought], timeout: 5)
        let staleProgress = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in session.currentTime < 17.9 }, object: nil)
        staleProgress.isInverted = true
        await fulfillment(of: [staleProgress], timeout: 1)
        let previousItem = try XCTUnwrap(session.player.currentItem)
        let player = session.player
        session.playEpisode(at: 0)
        XCTAssertTrue(session.player === player, "Changing episodes should reuse the native player's surface")
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: previousItem)
        await Task.yield()
        XCTAssertEqual(session.episodeOffset, 0)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            session.player.currentItem?.status == .readyToPlay
        }, object: nil)
        await fulfillment(of: [ready], timeout: 10)
        session.playsNextEpisode = false
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: session.player.currentItem)
        let paused = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in session.player.rate == 0 }, object: nil)
        await fulfillment(of: [paused], timeout: 3)
        XCTAssertEqual(session.episodeOffset, 0, "Disabling auto-play must stop at the episode boundary")
    }

    func testStoppedVideoIgnoresAnUncancellableSourceResponse() async {
        let entered = expectation(description: "source request entered")
        let engine = HeldVideoEngine(onRequest: { entered.fulfill() })
        let session = VideoPlaybackSession()
        session.start(configuration(chapters: episodes(hasDirectStreams: false), engine: engine, resume: nil))
        await fulfillment(of: [entered], timeout: 3)
        session.stop()
        await engine.release()
        await Task.yield()
        XCTAssertNil(session.player.currentItem)
        XCTAssertFalse(session.isLoading)
    }

    func testIdleSpeechStopDoesNotEraseAnotherRoutesNowPlayingRecord() {
        let owner = UUID()
        MediaPlaybackOwnership.shared.claim(owner) {}
        defer {
            _ = MediaPlaybackOwnership.shared.release(owner)
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "正在播放的视频"]
        ReaderSpeechController().stop()
        XCTAssertEqual(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "正在播放的视频")
        XCTAssertTrue(MediaPlaybackOwnership.shared.owns(owner))
    }

    func testNativeVideoControlsRenderInPortraitAndLandscape() async throws {
        let fixture = try XCTUnwrap(TestFixtureSupport.url(name: "episode", extension: "mp4", subdirectory: "media-playback"))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        defer { previous?.makeKey() }
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            let session = VideoPlaybackSession(makePlayerItem: { _ in AVPlayerItem(url: fixture) })
            let root = VideoPlayerView(bookTitle: "原生视频播放", source: .init(bookSourceName: "播放测试", bookSourceUrl: "https://video.fixture.invalid"),
                initialChapterIndex: 8, chapters: episodes(hasDirectStreams: true), engine: HeldVideoEngine(), playbackSession: session)
                .environmentObject(AppState())
            let host = UIHostingController(rootView: root)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.makeKeyAndVisible()
            XCTAssertTrue(host.view.window === window, "AVKit must mount in an actual application scene")
            defer { session.stop(); window.isHidden = true; window.rootViewController = nil }
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                session.player.currentItem?.status == .readyToPlay && self.findNativePlayer(in: host) != nil
            }, object: nil)
            await fulfillment(of: [ready], timeout: 15)
            let native = try XCTUnwrap(findNativePlayer(in: host))
            XCTAssertTrue(native.player === session.player)
            XCTAssertTrue(native.showsPlaybackControls)
            XCTAssertEqual(native.videoGravity, .resizeAspect)
            XCTAssertTrue(native.allowsPictureInPicturePlayback)
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = size.width < size.height ? "video-native-portrait" : "video-native-landscape"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func findNativePlayer(in controller: UIViewController) -> AVPlayerViewController? {
        if let player = controller as? AVPlayerViewController { return player }
        for child in controller.children {
            if let player = findNativePlayer(in: child) { return player }
        }
        return nil
    }

    private func episodes(hasDirectStreams: Bool) -> [BookChapter] {
        [2, 8].map { BookChapter(title: "第\($0)集", url: "https://video.fixture.invalid/\($0)" + (hasDirectStreams ? ".mp4" : ""),
            bookUrl: "https://video.fixture.invalid/book", index: $0) }
    }

    private func configuration(chapters: [BookChapter], engine: SourceEngine, resume: Double?) -> VideoPlaybackSession.Configuration {
        .init(bookID: nil, title: "视频样本", source: .init(bookSourceName: "视频样本源", bookSourceUrl: "https://video.fixture.invalid"),
            chapters: chapters, initialChapterIndex: 8, initialPositionSeconds: resume, engine: engine, bookshelf: nil)
    }
}

private actor HeldVideoEngine: SourceEngine {
    let onRequest: @Sendable () -> Void
    private var pending: (BookChapter, CheckedContinuation<Result<ChapterContent, SourceEngineError>, Never>)?
    init(onRequest: @escaping @Sendable () -> Void = {}) { self.onRequest = onRequest }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        await withCheckedContinuation { pending = (chapter, $0); onRequest() }
    }
    func release() {
        guard let (chapter, continuation) = pending else { return }
        pending = nil
        continuation.resume(returning: .success(.init(chapter: chapter, title: chapter.title, paragraphs: ["https://video.fixture.invalid/late.mp4"])))
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Unused video fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}
