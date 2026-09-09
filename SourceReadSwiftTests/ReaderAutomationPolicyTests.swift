import XCTest
import UIKit
@testable import SourceReadSwift

final class ReaderAutomationPolicyTests: XCTestCase {
    func testReaderChromeSettingsAlwaysExitsToOverlay() {
        var chrome = ReaderChromeStateMachine()
        XCTAssertEqual(chrome.mode, .hidden)

        chrome.toggleOverlay()
        XCTAssertEqual(chrome.mode, .overlay)

        chrome.openSettings()
        XCTAssertTrue(chrome.isSettingsVisible)
        chrome.closeSettings()
        XCTAssertEqual(chrome.mode, .overlay)
        XCTAssertTrue(chrome.isOverlayVisible)

        chrome.closeAll()
        XCTAssertEqual(chrome.mode, .hidden)
    }

    func testReaderChromeInitialStateAndRepeatedCloseAreIdempotent() {
        var chrome = ReaderChromeStateMachine()
        chrome.setInitialOverlayVisible(true)
        XCTAssertEqual(chrome.mode, .overlay)
        chrome.closeSettings()
        XCTAssertEqual(chrome.mode, .overlay)
        chrome.closeAll()
        chrome.closeAll()
        XCTAssertEqual(chrome.mode, .hidden)
    }

    func testReaderChromeToggleFromSettingsReturnsToOverlayBeforeHiding() {
        var chrome = ReaderChromeStateMachine()
        chrome.openSettings()
        XCTAssertEqual(chrome.mode, .settings)

        // The view-level toggle is intentionally a two-step exit: the first
        // tap closes settings, while the next tap hides the reader menu.
        chrome.closeSettings()
        XCTAssertEqual(chrome.mode, .overlay)
        chrome.toggleOverlay()
        XCTAssertEqual(chrome.mode, .hidden)
    }

    func testScrollTargetAccountsForContainerInsetAndClampsToContentBounds() {
        let target = ReaderScrollPositionPolicy.targetContentOffsetY(
            textRectMinY: 260,
            textContainerInsetTop: 24,
            boundsHeight: 400,
            contentSizeHeight: 1_200,
            adjustedContentInset: .init(top: 0, left: 0, bottom: 110, right: 0)
        )
        XCTAssertEqual(target, 236, accuracy: 0.001)

        let first = ReaderScrollPositionPolicy.targetContentOffsetY(
            textRectMinY: 0,
            textContainerInsetTop: 24,
            boundsHeight: 400,
            contentSizeHeight: 1_200,
            adjustedContentInset: .zero
        )
        XCTAssertEqual(first, 0, accuracy: 0.001)

        let last = ReaderScrollPositionPolicy.targetContentOffsetY(
            textRectMinY: 2_000,
            textContainerInsetTop: 24,
            boundsHeight: 400,
            contentSizeHeight: 1_200,
            adjustedContentInset: .init(top: 0, left: 0, bottom: 110, right: 0)
        )
        XCTAssertEqual(last, 910, accuracy: 0.001)

        let topInset = ReaderScrollPositionPolicy.targetContentOffsetY(
            textRectMinY: 0,
            textContainerInsetTop: 24,
            boundsHeight: 400,
            contentSizeHeight: 1_200,
            adjustedContentInset: .init(top: 20, left: 0, bottom: 0, right: 0)
        )
        XCTAssertEqual(topInset, -20, accuracy: 0.001)
    }

    func testAdvancesWithinCurrentChapter() {
        XCTAssertEqual(
            ReaderAutomationPolicy.decision(currentTarget: 2, maximumTarget: 5, canAdvanceChapter: true),
            .advance(to: 3)
        )
    }

    func testMovesToNextChapterAtBoundary() {
        XCTAssertEqual(
            ReaderAutomationPolicy.decision(currentTarget: 5, maximumTarget: 5, canAdvanceChapter: true),
            .nextChapter
        )
    }

    func testStopsAtFinalChapter() {
        XCTAssertEqual(
            ReaderAutomationPolicy.decision(currentTarget: 5, maximumTarget: 5, canAdvanceChapter: false),
            .stop
        )
    }

    func testAutoScrollDelayIsSafeForPersistedValues() {
        XCTAssertEqual(ReaderAutomationPolicy.clampedDelay(.nan), 2.0)
        XCTAssertEqual(ReaderAutomationPolicy.clampedDelay(.infinity), 2.0)
        XCTAssertEqual(ReaderAutomationPolicy.clampedDelay(-10), 0.25)
        XCTAssertEqual(ReaderAutomationPolicy.clampedDelay(120), 30)
    }

    func testAutoScrollStartSnapshotsVisibleParagraphInScrollMode() {
        XCTAssertEqual(
            ReaderAutomationPolicy.startingAutoScrollTarget(
                mode: .scroll,
                visibleParagraphIndex: 17,
                pagedPageIndex: 3,
                maximumTarget: 99
            ),
            17
        )
    }

    func testAutoScrollStartSnapshotsCurrentPageInPagedModes() {
        XCTAssertEqual(
            ReaderAutomationPolicy.startingAutoScrollTarget(
                mode: .pageTurn,
                visibleParagraphIndex: 17,
                pagedPageIndex: 8,
                maximumTarget: 99
            ),
            8
        )
        XCTAssertEqual(
            ReaderAutomationPolicy.startingAutoScrollTarget(
                mode: .cover,
                visibleParagraphIndex: 17,
                pagedPageIndex: 6,
                maximumTarget: 99
            ),
            6
        )
    }

    func testSpeechQueueFiltersEmptySegmentsAndPreservesIndexes() {
        var queue = ReaderSpeechQueue()
        queue.reset(title: " Title ", paragraphs: ["", "第一段", "  ", "第二段"])

        XCTAssertEqual(queue.dequeue()?.index, -1)
        XCTAssertEqual(queue.dequeue()?.text, "第一段")
        XCTAssertEqual(queue.dequeue()?.index, 3)
        XCTAssertNil(queue.dequeue())
        XCTAssertTrue(queue.isFinished)
    }

    func testSpeechQueueStartsAtVisibleParagraphWithoutReplayingChapterStart() {
        var queue = ReaderSpeechQueue()
        queue.reset(title: "标题", paragraphs: ["第一段", "第二段", "第三段"], startParagraphIndex: 1)

        XCTAssertEqual(queue.dequeue()?.index, 1)
        XCTAssertEqual(queue.dequeue()?.index, 2)
        XCTAssertNil(queue.dequeue())
    }

    func testSpeechQueueIncludesTitleOnlyAtChapterStart() {
        var queue = ReaderSpeechQueue()
        queue.reset(title: "标题", paragraphs: ["正文"], startParagraphIndex: 0, includeTitle: true)

        XCTAssertEqual(queue.dequeue()?.index, -1)
        XCTAssertEqual(queue.dequeue()?.index, 0)
        XCTAssertNil(queue.dequeue())
    }

    @MainActor
    func testPlaybackStateRejectsStaleGenerationAfterStop() {
        let coordinator = ReaderPlaybackCoordinator()
        let token = coordinator.beginAutoScroll()
        XCTAssertTrue(coordinator.accepts(token, for: .autoScroll(generation: token)))
        coordinator.stop()
        XCTAssertFalse(coordinator.accepts(token, for: .autoScroll(generation: token)))
    }

    @MainActor
    func testPlaybackStateTransitionsSpeechPauseAndResume() {
        let coordinator = ReaderPlaybackCoordinator()
        let token = coordinator.beginSpeech()
        coordinator.pauseSpeech()
        XCTAssertEqual(coordinator.mode, .pausedSpeech(generation: token))
        coordinator.resumeSpeech()
        XCTAssertEqual(coordinator.mode, .speech(generation: token))
        XCTAssertTrue(coordinator.accepts(token, for: .speech(generation: token)))
    }

    func testNativeReaderTextLayoutKeepsParagraphRangesAndSystemFonts() {
        let configuration = NativeReaderTextView.Configuration(
            title: "标题",
            subtitle: nil,
            paragraphs: ["第一段", "", "第二段"],
            contentFingerprint: "fixture",
            fontSize: 19,
            lineSpacing: 8,
            pagePadding: 24,
            letterSpacing: 0,
            paragraphSpacing: 16,
            paragraphIndent: 0,
            titleSpacing: 12,
            footerHeight: 72,
            textColor: .label,
            highlightColor: .systemBlue,
            animatedScrollDuration: 0.35
        )

        let result = ReaderNativeTextLayout.makeAttributedText(configuration: configuration)
        XCTAssertEqual(result.paragraphRanges.count, 3)
        XCTAssertEqual(result.text.string, "标题\n第一段\n\n第二段\n")
        XCTAssertEqual(result.paragraphRanges[0].length, "第一段".utf16.count)
        XCTAssertEqual(result.paragraphRanges[1].length, 0)
        XCTAssertEqual(result.paragraphRanges[2].length, "第二段".utf16.count)
        XCTAssertEqual(result.text.attribute(.font, at: result.paragraphRanges[0].location, effectiveRange: nil) as? UIFont, UIFont.systemFont(ofSize: 19))
    }

    func testNativeReaderConfigurationSeparatesTypographyFromInsetsAndTheme() {
        let base = NativeReaderTextView.Configuration(
            title: "标题",
            subtitle: nil,
            paragraphs: ["正文"],
            contentFingerprint: "fixture",
            fontSize: 19,
            lineSpacing: 8,
            pagePadding: 24,
            letterSpacing: 0,
            paragraphSpacing: 16,
            paragraphIndent: 0,
            titleSpacing: 12,
            footerHeight: 72,
            textColor: .label,
            highlightColor: .systemBlue,
            animatedScrollDuration: 0.35
        )
        let themeChanged = NativeReaderTextView.Configuration(
            title: "标题",
            subtitle: nil,
            paragraphs: ["正文"],
            contentFingerprint: "fixture",
            fontSize: 19,
            lineSpacing: 8,
            pagePadding: 24,
            letterSpacing: 0,
            paragraphSpacing: 16,
            paragraphIndent: 0,
            titleSpacing: 12,
            footerHeight: 72,
            textColor: .white,
            highlightColor: .systemYellow,
            animatedScrollDuration: 0.35
        )
        let insetChanged = NativeReaderTextView.Configuration(
            title: "标题",
            subtitle: nil,
            paragraphs: ["正文"],
            contentFingerprint: "fixture",
            fontSize: 19,
            lineSpacing: 8,
            pagePadding: 30,
            letterSpacing: 0,
            paragraphSpacing: 16,
            paragraphIndent: 0,
            titleSpacing: 12,
            footerHeight: 90,
            textColor: .label,
            highlightColor: .systemBlue,
            animatedScrollDuration: 0.35
        )

        XCTAssertEqual(base.textLayoutSignature, themeChanged.textLayoutSignature)
        XCTAssertNotEqual(base, themeChanged)
        XCTAssertEqual(base.insetsSignature, themeChanged.insetsSignature)
        XCTAssertNotEqual(base.insetsSignature, insetChanged.insetsSignature)
        XCTAssertEqual(base.textLayoutSignature, insetChanged.textLayoutSignature)
    }

    func testNativeReaderTextLayoutHandlesLongChaptersWithoutLosingParagraphRanges() {
        let paragraphs = (0..<2_500).map { index in
            "第\(index)段：这是用于长章节排版回归的中文正文。"
        }
        let configuration = NativeReaderTextView.Configuration(
            title: "长章节",
            subtitle: "性能回归",
            paragraphs: paragraphs,
            contentFingerprint: "long-fixture",
            fontSize: 19,
            lineSpacing: 8,
            pagePadding: 24,
            letterSpacing: 0,
            paragraphSpacing: 16,
            paragraphIndent: 0,
            titleSpacing: 12,
            footerHeight: 110,
            textColor: .label,
            highlightColor: .systemBlue,
            animatedScrollDuration: 0.35
        )

        let result = ReaderNativeTextLayout.makeAttributedText(configuration: configuration)
        XCTAssertEqual(result.paragraphRanges.count, paragraphs.count)
        XCTAssertEqual(result.paragraphRanges.first?.length, paragraphs[0].utf16.count)
        XCTAssertEqual(result.paragraphRanges.last?.length, paragraphs[2_499].utf16.count)
        XCTAssertEqual(result.text.string.components(separatedBy: "\n").count, paragraphs.count + 3)
    }
}
