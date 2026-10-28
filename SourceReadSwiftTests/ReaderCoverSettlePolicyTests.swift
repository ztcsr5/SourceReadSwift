import XCTest
@testable import SourceReadSwift

/// The cover surface owns its pan in a `UIScrollView`; the only decision left
/// in Swift is where a lifted finger lands. These cases pin the boundary
/// behaviour that used to live inline in `DragGesture.onEnded`.
final class ReaderCoverSettlePolicyTests: XCTestCase {
    private let width: CGFloat = 390

    func testPastHalfPageCommitsNext() {
        XCTAssertEqual(
            ReaderCoverSettlePolicy.outcome(
                contentOffsetX: width * 2,
                pageWidth: width,
                hasPrevious: true,
                hasNext: true
            ),
            .next
        )
    }

    func testPastHalfPageCommitsPrevious() {
        XCTAssertEqual(
            ReaderCoverSettlePolicy.outcome(
                contentOffsetX: 0,
                pageWidth: width,
                hasPrevious: true,
                hasNext: true
            ),
            .previous
        )
    }

    func testShortPullSpringsBack() {
        XCTAssertEqual(
            ReaderCoverSettlePolicy.outcome(
                contentOffsetX: width * 1.2,
                pageWidth: width,
                hasPrevious: true,
                hasNext: true
            ),
            .springBack
        )
    }

    func testBoundaryWithoutNeighbourSpringsBack() {
        XCTAssertEqual(
            ReaderCoverSettlePolicy.outcome(
                contentOffsetX: width * 2,
                pageWidth: width,
                hasPrevious: true,
                hasNext: false
            ),
            .springBack
        )
        XCTAssertEqual(
            ReaderCoverSettlePolicy.outcome(
                contentOffsetX: 0,
                pageWidth: width,
                hasPrevious: false,
                hasNext: true
            ),
            .springBack
        )
    }

    func testZeroWidthDoesNotDivideByZero() {
        XCTAssertEqual(
            ReaderCoverSettlePolicy.outcome(
                contentOffsetX: 0,
                pageWidth: 0,
                hasPrevious: true,
                hasNext: true
            ),
            .previous
        )
    }
}
