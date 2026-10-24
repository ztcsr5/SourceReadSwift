import XCTest
import CoreGraphics
@testable import SourceReadSwift

final class ReaderPagedNavigationPolicyTests: XCTestCase {
    // MARK: - Page cursor

    func testClampedPageIndexHandlesEmptyAndOutOfRange() {
        XCTAssertEqual(ReaderPagedNavigationPolicy.clampedPageIndex(-4, pageCount: 0), 0)
        XCTAssertEqual(ReaderPagedNavigationPolicy.clampedPageIndex(9, pageCount: 0), 0)
        XCTAssertEqual(ReaderPagedNavigationPolicy.clampedPageIndex(-4, pageCount: 6), 0)
        XCTAssertEqual(ReaderPagedNavigationPolicy.clampedPageIndex(2, pageCount: 6), 2)
        XCTAssertEqual(ReaderPagedNavigationPolicy.clampedPageIndex(99, pageCount: 6), 5)
    }

    func testClampedTargetsClampPageParagraphAndEmptyContent() {
        let result = ReaderPagedNavigationPolicy.clampedTargets(
            pageIndex: 99,
            paragraphIndex: 900,
            pageCount: 4,
            paragraphCount: 12
        )
        XCTAssertEqual(result.page, 3)
        XCTAssertEqual(result.paragraph, 11)

        let empty = ReaderPagedNavigationPolicy.clampedTargets(
            pageIndex: -2,
            paragraphIndex: 5,
            pageCount: 0,
            paragraphCount: 0
        )
        XCTAssertEqual(empty.page, 0)
        XCTAssertEqual(empty.paragraph, 0)
    }

    func testPageLookupUsesMonotonicParagraphStarts() {
        let starts = [0, 3, 7]
        XCTAssertEqual(ReaderPagedNavigationPolicy.page(containingParagraph: 0, pageFirstParagraphs: starts), 0)
        XCTAssertEqual(ReaderPagedNavigationPolicy.page(containingParagraph: 2, pageFirstParagraphs: starts), 0)
        XCTAssertEqual(ReaderPagedNavigationPolicy.page(containingParagraph: 3, pageFirstParagraphs: starts), 1)
        XCTAssertEqual(ReaderPagedNavigationPolicy.page(containingParagraph: 6, pageFirstParagraphs: starts), 1)
        XCTAssertEqual(ReaderPagedNavigationPolicy.page(containingParagraph: 7, pageFirstParagraphs: starts), 2)
        XCTAssertEqual(ReaderPagedNavigationPolicy.page(containingParagraph: 99, pageFirstParagraphs: starts), 2)
        XCTAssertEqual(ReaderPagedNavigationPolicy.page(containingParagraph: 3, pageFirstParagraphs: []), 0)
    }

    // MARK: - Cover swipe

    func testCoverSwipeCommitsNextOnLongLeftDrag() {
        let decision = ReaderCoverSwipePolicy.decision(
            translation: CGSize(width: -120, height: 8),
            predictedEndTranslation: CGSize(width: -210, height: 8),
            containerWidth: 390,
            pageIndex: 1,
            pageCount: 5
        )
        XCTAssertEqual(decision, .next)
    }

    func testCoverSwipeCommitsNextOnFastFlick() {
        let decision = ReaderCoverSwipePolicy.decision(
            translation: CGSize(width: -44, height: 2),
            predictedEndTranslation: CGSize(width: -160, height: 2),
            containerWidth: 390,
            pageIndex: 1,
            pageCount: 5
        )
        XCTAssertEqual(decision, .next)
    }

    func testCoverSwipeCommitsPreviousOnRightDrag() {
        let decision = ReaderCoverSwipePolicy.decision(
            translation: CGSize(width: 120, height: 4),
            predictedEndTranslation: CGSize(width: 190, height: 4),
            containerWidth: 390,
            pageIndex: 2,
            pageCount: 5
        )
        XCTAssertEqual(decision, .previous)
    }

    func testCoverSwipeCancelsAtPageBoundaries() {
        XCTAssertEqual(
            ReaderCoverSwipePolicy.decision(
                translation: CGSize(width: 140, height: 0),
                predictedEndTranslation: CGSize(width: 220, height: 0),
                containerWidth: 390,
                pageIndex: 0,
                pageCount: 5
            ),
            .cancel
        )
        XCTAssertEqual(
            ReaderCoverSwipePolicy.decision(
                translation: CGSize(width: -140, height: 0),
                predictedEndTranslation: CGSize(width: -220, height: 0),
                containerWidth: 390,
                pageIndex: 4,
                pageCount: 5
            ),
            .cancel
        )
    }

    func testCoverSwipeCancelsShortVerticalAndReversedPrediction() {
        XCTAssertEqual(
            ReaderCoverSwipePolicy.decision(
                translation: CGSize(width: -20, height: 0),
                predictedEndTranslation: CGSize(width: -20, height: 0),
                containerWidth: 390,
                pageIndex: 1,
                pageCount: 5
            ),
            .cancel
        )
        XCTAssertEqual(
            ReaderCoverSwipePolicy.decision(
                translation: CGSize(width: -60, height: 140),
                predictedEndTranslation: CGSize(width: -70, height: 180),
                containerWidth: 390,
                pageIndex: 1,
                pageCount: 5
            ),
            .cancel
        )
        XCTAssertEqual(
            ReaderCoverSwipePolicy.decision(
                translation: CGSize(width: -60, height: 0),
                predictedEndTranslation: CGSize(width: 120, height: 0),
                containerWidth: 390,
                pageIndex: 1,
                pageCount: 5
            ),
            .cancel
        )
    }

    func testCoverSwipeUsesContainerShareForSlowDrags() {
        // 50pt is below 18% of a 390pt page and has no flick prediction.
        XCTAssertEqual(
            ReaderCoverSwipePolicy.decision(
                translation: CGSize(width: -50, height: 0),
                predictedEndTranslation: CGSize(width: -50, height: 0),
                containerWidth: 390,
                pageIndex: 1,
                pageCount: 5
            ),
            .cancel
        )
        // The same distance on a compact 260pt page crosses the share.
        XCTAssertEqual(
            ReaderCoverSwipePolicy.decision(
                translation: CGSize(width: -50, height: 0),
                predictedEndTranslation: CGSize(width: -50, height: 0),
                containerWidth: 260,
                pageIndex: 1,
                pageCount: 5
            ),
            .next
        )
    }

    // MARK: - Page curl sync

    func testPageCurlSyncReloadsOnRevisionChange() {
        XCTAssertEqual(
            ReaderPageCurlSyncPolicy.decision(
                displayedIndex: 2,
                desiredIndex: 2,
                pageCount: 8,
                contentRevisionChanged: true,
                isUserInteracting: false
            ),
            .reloadCurrentPage
        )
    }

    func testPageCurlSyncMovesToDesiredPageAndClamps() {
        XCTAssertEqual(
            ReaderPageCurlSyncPolicy.decision(
                displayedIndex: 1,
                desiredIndex: 4,
                pageCount: 8,
                contentRevisionChanged: false,
                isUserInteracting: false
            ),
            .move(to: 4)
        )
        XCTAssertEqual(
            ReaderPageCurlSyncPolicy.decision(
                displayedIndex: 7,
                desiredIndex: 99,
                pageCount: 8,
                contentRevisionChanged: false,
                isUserInteracting: false
            ),
            .none
        )
        XCTAssertEqual(
            ReaderPageCurlSyncPolicy.decision(
                displayedIndex: nil,
                desiredIndex: 0,
                pageCount: 8,
                contentRevisionChanged: false,
                isUserInteracting: false
            ),
            .move(to: 0)
        )
    }

    func testPageCurlSyncNeverFightsTheUser() {
        XCTAssertEqual(
            ReaderPageCurlSyncPolicy.decision(
                displayedIndex: 2,
                desiredIndex: 5,
                pageCount: 8,
                contentRevisionChanged: true,
                isUserInteracting: true
            ),
            .none
        )
        XCTAssertEqual(
            ReaderPageCurlSyncPolicy.decision(
                displayedIndex: 2,
                desiredIndex: 5,
                pageCount: 0,
                contentRevisionChanged: false,
                isUserInteracting: false
            ),
            .none
        )
    }

    // MARK: - Long paragraph splitter

    func testTextSplitterKeepsShortText() {
        XCTAssertEqual(ReaderPageTextSplitter.split("短句。", maximumUTF16Length: 120), ["短句。"])
    }

    func testTextSplitterReconstructsOriginalAndRespectsBudget() {
        let sentence = "这是一段很长的正文，用来验证分页器不会把整段塞进一页。"
        let original = String(repeating: sentence, count: 40)
        let limit = 160
        let chunks = ReaderPageTextSplitter.split(original, maximumUTF16Length: limit)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(), original)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.utf16.count, limit + 2, "chunk exceeded budget: \(chunk.utf16.count)")
        }
    }

    func testTextSplitterFallsBackToHardCutWithoutPunctuation() {
        let original = String(repeating: "字", count: 500)
        let chunks = ReaderPageTextSplitter.split(original, maximumUTF16Length: 100)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.joined(), original)
    }

    // MARK: - Illustration budget

    func testSingleIllustrationFitsAvailablePageHeight() {
        let height = ReaderImageSizingPolicy.maximumHeight(
            for: .single,
            viewportHeight: 844,
            pagePadding: 20,
            footerHeight: 80
        )
        XCTAssertEqual(height, 628, accuracy: 0.5)
        XCTAssertLessThanOrEqual(height, 844 - 40 - 80)
    }

    func testStandardIllustrationLeavesRoomForText() {
        let height = ReaderImageSizingPolicy.maximumHeight(
            for: .standard,
            viewportHeight: 844,
            pagePadding: 20,
            footerHeight: 80
        )
        XCTAssertLessThanOrEqual(height, 628)
        XCTAssertLessThan(height, 844 * 0.7)
    }
}
