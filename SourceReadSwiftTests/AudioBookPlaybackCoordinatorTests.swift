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

    func testStartingAnEmptyBookRejectsThePreviousChaptersLateResponse() async throws {
        let requested = expectation(description: "old chapter request entered")
        let engine = HeldAudioChapterEngine(onRequest: { requested.fulfill() })
        let coordinator = AudioBookPlaybackCoordinator.shared
        let source = BookSource(bookSourceName: "音频回归", bookSourceUrl: "https://audio.fixture.invalid")
        let book = SearchBook(name: "旧书", author: nil, coverUrl: nil, bookUrl: source.bookSourceUrl + "/book",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        let chapter = BookChapter(title: "旧章节", url: book.bookUrl + "/chapter", bookUrl: book.bookUrl, index: 0)
        coordinator.startBook(book: book, source: source, chapters: [chapter], engine: engine)
        await fulfillment(of: [requested], timeout: 2)
        let emptyBook = SearchBook(name: "空目录新书", author: nil, coverUrl: nil, bookUrl: source.bookSourceUrl + "/empty",
            sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        coordinator.startBook(book: emptyBook, source: source, chapters: [], engine: engine)
        await engine.release(chapter)
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(coordinator.currentBook?.bookUrl, emptyBook.bookUrl)
        XCTAssertFalse(coordinator.isLoading)
        XCTAssertFalse(coordinator.isPlaying)
        XCTAssertNil(coordinator.currentAudioURL)
        XCTAssertNil(coordinator.currentChapter)
        XCTAssertEqual(coordinator.errorMessage, "此书暂无可播放章节")
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

private actor HeldAudioChapterEngine: SourceEngine {
    private let onRequest: @Sendable () -> Void
    private var pending: CheckedContinuation<Result<ChapterContent, SourceEngineError>, Never>?
    init(onRequest: @escaping @Sendable () -> Void) { self.onRequest = onRequest }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        await withCheckedContinuation { pending = $0; onRequest() }
    }
    func release(_ chapter: BookChapter) {
        pending?.resume(returning: .success(ChapterContent(chapter: chapter, title: chapter.title,
            paragraphs: ["http://127.0.0.1:9/obsolete.mp3"])))
        pending = nil
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.rule("Unused audio fixture method")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .success([]) }
}
