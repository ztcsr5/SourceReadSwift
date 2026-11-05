import XCTest
@testable import SourceReadSwift

@MainActor
final class AudioBookPlaybackCoordinatorTests: XCTestCase {

    override func setUp() async throws {
        AudioBookPlaybackCoordinator.shared.stop()
        AudioBookPlaybackCoordinator.shared.setPlaybackRate(1)
    }

    override func tearDown() async throws {
        AudioBookPlaybackCoordinator.shared.stop()
    }

    func testPlayWithoutAnActivePlayerKeepsPlaybackStopped() {
        let coordinator = AudioBookPlaybackCoordinator.shared
        coordinator.play()
        XCTAssertFalse(coordinator.isPlaying)
    }

    func testStopClearsLoadingAndChapterState() {
        let coordinator = AudioBookPlaybackCoordinator.shared
        coordinator.chapters = [BookChapter(title: "旧章节", url: "https://fixture.invalid/1", bookUrl: "book", index: 0)]
        coordinator.isLoading = true
        coordinator.errorMessage = "旧加载错误"
        coordinator.stop()
        XCTAssertFalse(coordinator.isLoading)
        XCTAssertTrue(coordinator.chapters.isEmpty)
        XCTAssertNil(coordinator.currentChapter)
        XCTAssertNil(coordinator.errorMessage)
    }

    func testNonfiniteProgressNeverEscapesIntoTheSeekSlider() {
        let coordinator = AudioBookPlaybackCoordinator.shared
        coordinator.duration = .infinity
        coordinator.currentTime = .infinity
        XCTAssertEqual(coordinator.progress, 0)
    }

    func testInitialState() {
        let coordinator = AudioBookPlaybackCoordinator.shared
        XCTAssertNotNil(coordinator)
        XCTAssertEqual(coordinator.playbackRate, 1.0)
        XCTAssertFalse(coordinator.stopAtChapterEnd)
    }

    func testSetPlaybackRate() {
        let coordinator = AudioBookPlaybackCoordinator.shared
        coordinator.setPlaybackRate(1.5)
        XCTAssertEqual(coordinator.playbackRate, 1.5)
        coordinator.setPlaybackRate(1.0)
    }

    func testSleepTimerSettings() {
        let coordinator = AudioBookPlaybackCoordinator.shared
        coordinator.setSleepTimer(minutes: 30)
        XCTAssertEqual(coordinator.sleepTimerMinutesRemaining, 30)
        XCTAssertFalse(coordinator.stopAtChapterEnd)

        // Chapter end
        coordinator.setSleepTimer(minutes: 0)
        XCTAssertNil(coordinator.sleepTimerMinutesRemaining)
        XCTAssertTrue(coordinator.stopAtChapterEnd)

        // Disable
        coordinator.setSleepTimer(minutes: nil)
        XCTAssertNil(coordinator.sleepTimerMinutesRemaining)
        XCTAssertFalse(coordinator.stopAtChapterEnd)
    }

    func testPlaybackProgressCalculation() {
        let coordinator = AudioBookPlaybackCoordinator.shared
        coordinator.currentTime = 0
        coordinator.duration = 0
        XCTAssertEqual(coordinator.progress, 0.0)

        coordinator.duration = 100
        coordinator.currentTime = 50
        XCTAssertEqual(coordinator.progress, 0.5)

        coordinator.currentTime = 150
        XCTAssertEqual(coordinator.progress, 1.0)
    }
}
