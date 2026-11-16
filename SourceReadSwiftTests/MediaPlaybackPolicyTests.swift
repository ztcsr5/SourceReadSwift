import XCTest
@testable import SourceReadSwift

final class MediaPlaybackPolicyTests: XCTestCase {
    func testResumeWaitsForDurationInsteadOfClampingSavedPositionToZero() {
        XCTAssertEqual(MediaPlaybackPolicy.resume(at: 19, duration: .nan), .waitForDuration)
        XCTAssertEqual(MediaPlaybackPolicy.resume(at: 19, duration: 60), .seek(19))
        XCTAssertEqual(MediaPlaybackPolicy.resume(at: 60, duration: 60), .fromStart)
        XCTAssertEqual(MediaPlaybackPolicy.resume(at: .infinity, duration: 60), .fromStart)
        XCTAssertNil(MediaPlaybackPolicy.recordedSecond(.nan))
        XCTAssertNil(MediaPlaybackPolicy.recordedSecond(Double(Int.max)))
        XCTAssertEqual(MediaPlaybackPolicy.recordedSecond(12.9), 12)
    }

    func testSavedIdentityIsResolvedBeforeTheOffsetCompatibilityFallback() {
        let chapters = [0, 2, 8].map { BookChapter(title: "第\($0)回",
            url: "https://fixture.invalid/\($0)", bookUrl: "https://fixture.invalid/book", index: $0) }
        XCTAssertEqual(MediaPlaybackPolicy.episodeOffset(for: 2, in: chapters), 1)
        XCTAssertEqual(MediaPlaybackPolicy.episodeOffset(for: 8, in: chapters), 2)
        XCTAssertEqual(MediaPlaybackPolicy.episodeOffset(for: 1, in: chapters), 1)
    }

    @MainActor
    func testNewRouteStopsPreviousOwnerAndStaleReleaseCannotClearIt() {
        let channel = MediaPlaybackOwnership()
        let audio = UUID()
        let video = UUID()
        var relinquishedAudio = false
        channel.claim(audio) {
            relinquishedAudio = true
            XCTAssertFalse(channel.release(audio))
        }
        channel.claim(video) { XCTFail("The active route must not yield") }
        XCTAssertTrue(relinquishedAudio)
        XCTAssertFalse(channel.owns(audio))
        XCTAssertTrue(channel.owns(video))
        XCTAssertTrue(channel.release(video))
    }
}
