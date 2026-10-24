import XCTest
@testable import SourceReadSwift

final class ReaderChapterWindowPolicyTests: XCTestCase {
    func testRadiusAlwaysKeepsOneChapterOnEachSide() {
        XCTAssertEqual(ReaderChapterWindowPolicy.radius(forPreloadCount: 0), 1)
        XCTAssertEqual(ReaderChapterWindowPolicy.radius(forPreloadCount: 2), 2)
        XCTAssertEqual(ReaderChapterWindowPolicy.radius(forPreloadCount: 99), ReaderPreloadPolicy.maximumCount)
    }

    func testWindowIndicesClampAtBookEdges() {
        XCTAssertEqual(
            ReaderChapterWindowPolicy.indices(around: 0, radius: 2, lowerBound: 0, upperBound: 10),
            [0, 1, 2]
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.indices(around: 9, radius: 2, lowerBound: 0, upperBound: 10),
            [7, 8, 9]
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.indices(around: 5, radius: 2, lowerBound: 0, upperBound: 10),
            [3, 4, 5, 6, 7]
        )
        XCTAssertTrue(
            ReaderChapterWindowPolicy.indices(around: 0, radius: 2, lowerBound: 0, upperBound: 0).isEmpty
        )
    }

    func testPrefetchOrderIsNearestFirstAndPrefersForward() {
        let order = ReaderChapterWindowPolicy.prefetchOrder(
            current: 5,
            radius: 2,
            lowerBound: 0,
            upperBound: 10,
            loaded: [3, 5, 7]
        )
        XCTAssertEqual(order, [6, 4])
        XCTAssertEqual(
            ReaderChapterWindowPolicy.prefetchOrder(
                current: 5,
                radius: 2,
                lowerBound: 0,
                upperBound: 10,
                loaded: []
            ),
            [6, 4, 7, 3]
        )
    }

    func testPrefetchOrderAlwaysSkipsTheCursorChapter() {
        let order = ReaderChapterWindowPolicy.prefetchOrder(
            current: 5,
            radius: 2,
            lowerBound: 0,
            upperBound: 10,
            loaded: []
        )
        XCTAssertFalse(order.contains(5))
        XCTAssertEqual(order, [6, 4, 7, 3])
    }

    func testChapterPositionKeepsPageOrdinal() {
        let position = ReaderChapterPosition(chapterIndex: 8, paragraphIndex: 12, pageOrdinal: 3)
        XCTAssertEqual(position.pageOrdinal, 3)
        XCTAssertEqual(position, ReaderChapterPosition(chapterIndex: 8, paragraphIndex: 12, pageOrdinal: 3))
        XCTAssertNotEqual(position, ReaderChapterPosition(chapterIndex: 8, paragraphIndex: 12, pageOrdinal: 2))
    }

    func testNextMissingIndexWalksBothDirections() {
        let loaded: Set<Int> = [4, 5, 6]
        XCTAssertEqual(
            ReaderChapterWindowPolicy.nextMissingIndex(
                direction: 1, current: 5, lowerBound: 0, upperBound: 10, loaded: loaded
            ),
            7
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.nextMissingIndex(
                direction: -1, current: 5, lowerBound: 0, upperBound: 10, loaded: loaded
            ),
            3
        )
        XCTAssertNil(
            ReaderChapterWindowPolicy.nextMissingIndex(
                direction: 1, current: 9, lowerBound: 0, upperBound: 10, loaded: loaded
            )
        )
    }

    func testRetainedIndicesKeepLoadingChaptersAndTheCursor() {
        let keep = ReaderChapterWindowPolicy.retainedIndices(
            around: 5,
            radius: 1,
            lowerBound: 0,
            upperBound: 10,
            loading: [7]
        )
        XCTAssertEqual(keep, [4, 5, 6, 7])
        let cursorOutsideRadius = ReaderChapterWindowPolicy.retainedIndices(
            around: 5,
            radius: 0,
            lowerBound: 0,
            upperBound: 10,
            loading: []
        )
        XCTAssertEqual(cursorOutsideRadius, [5])
        XCTAssertTrue(
            ReaderChapterWindowPolicy.retainedIndices(
                around: 0,
                radius: 1,
                lowerBound: 0,
                upperBound: 0,
                loading: [3]
            ).isEmpty
        )
    }

    func testLayoutUsesOneDividerBetweenChapters() {
        let layout = ReaderChapterWindowPolicy.layout([
            ReaderChapterSlice(chapterIndex: 5, paragraphCount: 3),
            ReaderChapterSlice(chapterIndex: 6, paragraphCount: 4)
        ])
        XCTAssertEqual(layout.totalCount, 8)
        XCTAssertEqual(layout.slots.count, 2)
        XCTAssertNil(layout.slots[0].headerIndex)
        XCTAssertEqual(layout.slots[1].headerIndex, 3)
        XCTAssertEqual(layout.paragraphStart(chapterIndex: 5), 0)
        XCTAssertEqual(layout.paragraphStart(chapterIndex: 6), 4)
        XCTAssertEqual(layout.flatIndex(chapterIndex: 6, paragraphIndex: 2), 6)
        XCTAssertEqual(layout.flatIndex(chapterIndex: 6, paragraphIndex: Int.max), 7)
        XCTAssertEqual(layout.flatIndex(chapterIndex: 6, paragraphIndex: -4), 4)
        XCTAssertNil(layout.flatIndex(chapterIndex: 99, paragraphIndex: 0))
    }

    func testResolvedPositionMapsDividerToPreviousChapterTail() {
        let layout = ReaderChapterWindowPolicy.layout([
            ReaderChapterSlice(chapterIndex: 5, paragraphCount: 3),
            ReaderChapterSlice(chapterIndex: 6, paragraphCount: 4)
        ])
        XCTAssertEqual(
            ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 0, layout: layout),
            ReaderChapterPosition(chapterIndex: 5, paragraphIndex: 0)
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 2, layout: layout),
            ReaderChapterPosition(chapterIndex: 5, paragraphIndex: 2)
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 3, layout: layout),
            ReaderChapterPosition(chapterIndex: 5, paragraphIndex: 2)
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 4, layout: layout),
            ReaderChapterPosition(chapterIndex: 6, paragraphIndex: 0)
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 999, layout: layout),
            ReaderChapterPosition(chapterIndex: 6, paragraphIndex: 3)
        )
        XCTAssertNil(ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 0, layout: .init(slots: [])))
    }

    func testFlatShiftMeasuresPrependWithoutTouchingTheAnchor() {
        let old = [
            ReaderChapterSlice(chapterIndex: 5, paragraphCount: 10),
            ReaderChapterSlice(chapterIndex: 6, paragraphCount: 10)
        ]
        let new = [
            ReaderChapterSlice(chapterIndex: 4, paragraphCount: 5),
            ReaderChapterSlice(chapterIndex: 5, paragraphCount: 10),
            ReaderChapterSlice(chapterIndex: 6, paragraphCount: 10)
        ]
        XCTAssertEqual(
            ReaderChapterWindowPolicy.flatShift(oldSlices: old, newSlices: new, anchorChapterIndex: 6),
            6
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.flatShift(oldSlices: old, newSlices: new, anchorChapterIndex: 5),
            6
        )
    }

    func testTrimShiftIsNegativeAndBounded() {
        let old = [
            ReaderChapterSlice(chapterIndex: 3, paragraphCount: 8),
            ReaderChapterSlice(chapterIndex: 4, paragraphCount: 6),
            ReaderChapterSlice(chapterIndex: 5, paragraphCount: 7)
        ]
        let new = [
            ReaderChapterSlice(chapterIndex: 4, paragraphCount: 6),
            ReaderChapterSlice(chapterIndex: 5, paragraphCount: 7)
        ]
        XCTAssertEqual(
            ReaderChapterWindowPolicy.flatShift(oldSlices: old, newSlices: new, anchorChapterIndex: 4),
            -9
        )
    }

    func testEmptyChapterNeverOwnsAParagraph() {
        let layout = ReaderChapterWindowPolicy.layout([
            ReaderChapterSlice(chapterIndex: 1, paragraphCount: 0),
            ReaderChapterSlice(chapterIndex: 2, paragraphCount: 2)
        ])
        XCTAssertEqual(layout.totalCount, 3)
        XCTAssertEqual(
            ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 0, layout: layout),
            ReaderChapterPosition(chapterIndex: 2, paragraphIndex: 0)
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 1, layout: layout),
            ReaderChapterPosition(chapterIndex: 2, paragraphIndex: 0)
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.resolvedPosition(flatIndex: 2, layout: layout),
            ReaderChapterPosition(chapterIndex: 2, paragraphIndex: 1)
        )
    }

    func testPlaceholderRestoreUsesTravelDirection() {
        XCTAssertEqual(
            ReaderChapterWindowPolicy.restoreParagraphIndex(
                chapterIndex: 4, currentChapterIndex: 5, placeholderDirection: -1
            ),
            Int.max
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.restoreParagraphIndex(
                chapterIndex: 6, currentChapterIndex: 5, placeholderDirection: 1
            ),
            0
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.restoreParagraphIndex(
                chapterIndex: 4, currentChapterIndex: 5, placeholderDirection: 0
            ),
            Int.max
        )
        XCTAssertEqual(
            ReaderChapterWindowPolicy.restoreParagraphIndex(
                chapterIndex: 6, currentChapterIndex: 5, placeholderDirection: 0
            ),
            0
        )
    }

    func testFirstAndLastPageResolutionSkipsPlaceholders() {
        let pages: [(chapterIndex: Int, isPlaceholder: Bool)] = [
            (3, true),
            (4, false),
            (4, false),
            (5, true)
        ]
        XCTAssertEqual(ReaderChapterWindowPolicy.firstPageIndex(chapterIndex: 4, in: pages), 1)
        XCTAssertEqual(ReaderChapterWindowPolicy.lastPageIndex(chapterIndex: 4, in: pages), 2)
        XCTAssertNil(ReaderChapterWindowPolicy.lastPageIndex(chapterIndex: 5, in: pages))
        XCTAssertEqual(ReaderChapterWindowPolicy.firstPageIndex(chapterIndex: 6, in: pages), 3)
    }
}