import XCTest
import UIKit
@testable import SourceReadSwift

final class ReaderAutomationPolicyTests: XCTestCase {
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
        XCTAssertEqual(result.text.string, "标题\n第一段\n\n\n\n第二段\n\n")
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
        XCTAssertEqual(result.text.string.components(separatedBy: "\n\n").count, paragraphs.count + 2)
    }
}
