import XCTest
import Foundation
import CoreGraphics
import QuartzCore
import UIKit
@testable import SourceReadSwift

final class ReaderPerformancePolicyTests: XCTestCase {
    @MainActor func testFrameRateAnchorDoesNotKeepItsWindowAlive() {
        let anchor = FrameRateSceneAnchor.AnchorView()
        weak var releasedWindow: UIWindow?
        autoreleasepool {
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.addSubview(anchor)
            anchor.applyIfNeeded()
            releasedWindow = window
            XCTAssertNotNil(anchor.window)
        }
        XCTAssertNil(releasedWindow, "The refresh-rate anchor must not retain an otherwise released window")
    }

    func testRefreshRateNeverExceedsDeviceOr120HzCeiling() {
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 60), 60)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 120), 120)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 144), 120)
        XCTAssertEqual(ReaderPerformancePolicy.preferredRefreshRate(maximumFramesPerSecond: 0), 0)
        XCTAssertTrue(ReaderPerformancePolicy.disablesMinimumFrameDuration)
    }

    func testPreferredFrameRateRangeTargetsHighRefreshOnlyWhenSupported() {
        let proMotion = FrameRateCoordinator.preferredRange(maximumFramesPerSecond: 120)
        XCTAssertEqual(proMotion?.minimum, 80)
        XCTAssertEqual(proMotion?.maximum, 120)
        XCTAssertEqual(proMotion?.preferred, 120)

        let standard = FrameRateCoordinator.preferredRange(maximumFramesPerSecond: 60)
        XCTAssertEqual(standard?.minimum, 60)
        XCTAssertEqual(standard?.maximum, 60)
        XCTAssertEqual(standard?.preferred, 60)

        XCTAssertNil(FrameRateCoordinator.preferredRange(maximumFramesPerSecond: 0))
    }

    func testAdaptiveFrameRatePlanUsesOneHzFloorAndDeviceCeiling() {
        XCTAssertEqual(
            ReaderPerformancePolicy.frameRatePlan(maximumFramesPerSecond: 120),
            .init(minimum: 1, maximum: 120, preferred: 120)
        )
        XCTAssertEqual(
            ReaderPerformancePolicy.frameRatePlan(maximumFramesPerSecond: 60),
            .init(minimum: 1, maximum: 60, preferred: 60)
        )
        XCTAssertEqual(
            ReaderPerformancePolicy.frameRatePlan(maximumFramesPerSecond: 0),
            .init(minimum: 1, maximum: 0, preferred: 0)
        )
    }

    func testViewportCacheKeyAndPageMetricsAreDeterministic() {
        XCTAssertEqual(ReaderPerformancePolicy.viewportCacheKey(.init(width: 390.4, height: 844.6)), "390x845")
        let compact = ReaderPerformancePolicy.pageMetrics(
            viewportSize: .init(width: 390, height: 844),
            pagePadding: 24,
            footerHeight: 72,
            fontSize: 19,
            lineSpacing: 8,
            letterSpacing: 0
        )
        let wider = ReaderPerformancePolicy.pageMetrics(
            viewportSize: .init(width: 844, height: 390),
            pagePadding: 24,
            footerHeight: 72,
            fontSize: 19,
            lineSpacing: 8,
            letterSpacing: 0
        )
        XCTAssertGreaterThan(compact.pageBudget, 0)
        XCTAssertGreaterThan(wider.charsPerLine, compact.charsPerLine)
        XCTAssertGreaterThanOrEqual(compact.linesPerPage, 8)
    }

    func testVisibleParagraphResolverUsesRangeIntersection() {
        let ranges = [
            NSRange(location: 0, length: 10),
            NSRange(location: 12, length: 8),
            NSRange(location: 22, length: 7)
        ]
        XCTAssertEqual(
            ReaderParagraphIndexResolver.firstVisibleIndex(in: ranges, visibleRange: NSRange(location: 14, length: 2)),
            1
        )
        XCTAssertEqual(
            ReaderParagraphIndexResolver.firstVisibleIndex(in: ranges, visibleRange: NSRange(location: 10, length: 2)),
            1
        )
        XCTAssertNil(ReaderParagraphIndexResolver.firstVisibleIndex(in: ranges, visibleRange: NSRange(location: 0, length: 0)))
        XCTAssertNil(ReaderParagraphIndexResolver.firstVisibleIndex(in: [], visibleRange: NSRange(location: 0, length: 3)))
    }

    func testParagraphTrackingScalesForLongChapters() {
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 180), 1)
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 181), 3)
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 600), 3)
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 601), 5)
        XCTAssertEqual(ReaderPerformancePolicy.paragraphTrackingStride(paragraphCount: 1_501), 8)
    }

    func testPersistenceDebounceIsLongerThanOneFrame() {
        XCTAssertGreaterThan(ReaderPerformancePolicy.positionPersistenceDebounceNanoseconds, 16_000_000)
    }

    func testPageLayoutDebounceCoalescesSliderUpdates() {
        XCTAssertGreaterThan(ReaderPerformancePolicy.pageLayoutDebounceNanoseconds, 16_000_000)
        XCTAssertLessThan(ReaderPerformancePolicy.pageLayoutDebounceNanoseconds, 500_000_000)
    }

    func testVisibleParagraphUpdatesAreThrottledBelowDisplayCadence() {
        XCTAssertGreaterThanOrEqual(ReaderPerformancePolicy.visibleParagraphUpdateInterval, 0.05)
        XCTAssertLessThan(ReaderPerformancePolicy.visibleParagraphUpdateInterval, 0.2)
    }

    func testPagedWarmupAndSettleConstantsStayCheap() {
        // One frame at 120 Hz is 8.33 ms; the settle debounce must clear the
        // geometry noise but stay well under the old 320 ms stall.
        XCTAssertGreaterThan(ReaderPerformancePolicy.geometrySettleNanoseconds, 16_000_000)
        XCTAssertLessThan(ReaderPerformancePolicy.geometrySettleNanoseconds, 160_000_000)
        XCTAssertGreaterThan(ReaderPerformancePolicy.paginationWarmupRestartNanoseconds, 16_000_000)
        XCTAssertGreaterThan(ReaderPerformancePolicy.paginationWarmupBatchSize, 0)
        XCTAssertLessThanOrEqual(ReaderPerformancePolicy.paginationWarmupBatchSize, 8)
        XCTAssertLessThan(ReaderPerformancePolicy.paginationWarmupInterBatchNanoseconds, 16_000_000)
        XCTAssertGreaterThan(ReaderPerformancePolicy.coverCommitFallbackNanoseconds, 100_000_000)
        XCTAssertLessThan(ReaderPerformancePolicy.coverCommitFallbackNanoseconds, 1_500_000_000)
    }

    func testCoverSlotsAlwaysCoverTheDeclaredRadius() {
        XCTAssertEqual(
            ReaderPerformancePolicy.coverPageSlotCount,
            ReaderPerformancePolicy.coverPageSlotRadius * 2 + 1
        )
        XCTAssertGreaterThanOrEqual(ReaderPerformancePolicy.coverPageSlotRadius, 1)
    }

    @MainActor
    func testSharedClockComputesNextMinuteDelayAndLifecycle() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dateA = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9, minute: 12, second: 42))!
        let dateB = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9, minute: 12, second: 59))!
        let dateC = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 9, minute: 13, second: 0))!

        XCTAssertTrue(ReaderSharedClock.isSameMinute(dateA, dateB, calendar: calendar))
        XCTAssertFalse(ReaderSharedClock.isSameMinute(dateA, dateC, calendar: calendar))
        XCTAssertEqual(ReaderSharedClock.nextMinuteDelay(from: dateA, calendar: calendar), 18.0, accuracy: 0.05)

        let clock = ReaderSharedClock(initialDate: dateA)
        let t1 = UUID()
        let t2 = UUID()
        clock.register(token: t1)
        clock.register(token: t2)
        XCTAssertEqual(clock.activeSubscriberCount, 2)
        clock.unregister(token: t1)
        XCTAssertEqual(clock.activeSubscriberCount, 1)
        clock.unregister(token: t2)
        XCTAssertEqual(clock.activeSubscriberCount, 0)
    }

    func testPaginationSchedulingPolicyAndOffMainActorPaginator() async {
        XCTAssertFalse(
            ReaderPaginationSchedulingPolicy.shouldPaginateOffMainActor(
                hasExistingPages: false,
                activeChapterCharacterCount: ReaderPerformancePolicy.inlinePaginationCharacterThreshold,
                forceAsync: false
            )
        )
        XCTAssertTrue(
            ReaderPaginationSchedulingPolicy.shouldPaginateOffMainActor(
                hasExistingPages: false,
                activeChapterCharacterCount: ReaderPerformancePolicy.inlinePaginationCharacterThreshold + 1,
                forceAsync: false
            )
        )
        XCTAssertTrue(
            ReaderPaginationSchedulingPolicy.shouldPaginateOffMainActor(
                hasExistingPages: true,
                activeChapterCharacterCount: 120,
                forceAsync: false
            )
        )
        XCTAssertTrue(
            ReaderPaginationSchedulingPolicy.shouldPaginateOffMainActor(
                hasExistingPages: false,
                activeChapterCharacterCount: 120,
                forceAsync: true
            )
        )

        let typography = ReaderPageTypography(
            font: UIFont.systemFont(ofSize: 18),
            titleFont: UIFont.boldSystemFont(ofSize: 22),
            lineSpacing: 6,
            letterSpacing: 0.35,
            paragraphSpacing: 10,
            firstLineIndent: 36,
            titleSpacing: 8,
            contentWidth: 348,
            contentHeight: 520
        )
        let context = ReaderChapterPaginationContext(
            typography: typography,
            titleTypography: typography,
            chromeLayout: .header,
            imageStyle: .standard,
            viewportHeight: 844,
            pagePadding: 21,
            footerHeight: 14,
            traditionalChinese: false
        )
        let paragraphs = (0..<24).map { "第 \($0 + 1) 段：异步分页测试文本，保证排版和行高与主线程分页完全一致。" }
        let expected = ReaderChapterPaginator.paginate(
            chapterIndex: 3,
            title: "第三章",
            paragraphs: paragraphs,
            context: context
        )
        let outputs = await ReaderOffMainActorPaginator.paginateChapters(
            [
                ReaderOffMainActorPaginator.ChapterInput(
                    chapterIndex: 3,
                    title: "第三章",
                    paragraphs: paragraphs,
                    contentSignature: "3|rev1"
                )
            ],
            context: context
        )
        XCTAssertEqual(outputs.count, 1)
        XCTAssertEqual(outputs[0].chapterIndex, 3)
        XCTAssertEqual(outputs[0].contentSignature, "3|rev1")
        XCTAssertEqual(outputs[0].blocks.count, expected.count)
    }

    @MainActor
    func testChapterContentCacheStoreMaintainsEstimatedBytesIncrementalParity() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-bytes-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: dir), maxEntryCount: 10)
        XCTAssertEqual(store.estimatedByteCount, 0)

        let ch1 = BookChapter(title: "第1章", url: "https://example.com/1", bookUrl: "https://example.com/book", index: 0)
        let ch2 = BookChapter(title: "第2章", url: "https://example.com/2", bookUrl: "https://example.com/book", index: 1)
        store.save(ChapterContent(chapter: ch1, title: ch1.title, paragraphs: ["第一段文本", "第二段较长文本内容"]), sourceURL: "https://example.com", purifyRules: [])
        store.save(ChapterContent(chapter: ch2, title: ch2.title, paragraphs: ["第三段内容"]), sourceURL: "https://example.com", purifyRules: [])

        let expectedAfterSave = store.entries.reduce(0) { $0 + $1.estimatedByteCount }
        XCTAssertGreaterThan(expectedAfterSave, 0)
        XCTAssertEqual(store.estimatedByteCount, expectedAfterSave)

        // Overwrite chapter 1 with shorter content and verify parity.
        store.save(ChapterContent(chapter: ch1, title: ch1.title, paragraphs: ["短"]), sourceURL: "https://example.com", purifyRules: [])
        XCTAssertEqual(store.estimatedByteCount, store.entries.reduce(0) { $0 + $1.estimatedByteCount })

        let firstKey = try XCTUnwrap(store.entries.first?.key)
        store.remove(key: firstKey)
        XCTAssertEqual(store.estimatedByteCount, store.entries.reduce(0) { $0 + $1.estimatedByteCount })

        store.removeAll()
        XCTAssertEqual(store.estimatedByteCount, 0)
    }

    @MainActor
    func testReaderChromeSleepCoordinatorsAndTextCacheContains() {
        let coordinators = ReaderRuntimeCoordinators()
        XCTAssertFalse(coordinators.chrome.isOverlayVisible)
        XCTAssertFalse(coordinators.chrome.isSettingsVisible)
        coordinators.chrome.state.openSettings()
        XCTAssertTrue(coordinators.chrome.isSettingsVisible)
        coordinators.chrome.settingsTab = 2
        XCTAssertEqual(coordinators.chrome.settingsTab, 2)
        coordinators.chrome.state.closeAll()
        XCTAssertFalse(coordinators.chrome.isOverlayVisible)

        coordinators.sleepTimer.remainingSeconds = 95
        XCTAssertEqual(coordinators.sleepTimer.badgeText(configuredMinutes: 5), "1:35")
        XCTAssertEqual(coordinators.sleepTimer.badgeText(configuredMinutes: -1), "播完当章")

        let cache = ReaderPageTextCache()
        XCTAssertFalse(cache.contains(key: "p0", signature: "sig1"))
        _ = cache.text(key: "p0", signature: "sig1") { NSAttributedString(string: "hello") }
        XCTAssertTrue(cache.contains(key: "p0", signature: "sig1"))
        XCTAssertFalse(cache.contains(key: "p0", signature: "sig2"))
    }

    func testReaderPaperTextureAsyncCachesGeneratedTexture() async {
        let generated = await ReaderPaperTexture.loadAsync(background: .linen, night: false)
        XCTAssertGreaterThan(generated.size.width, 0)
        XCTAssertNotNil(ReaderPaperTexture.cachedImage(background: .linen, night: false))
    }
}
