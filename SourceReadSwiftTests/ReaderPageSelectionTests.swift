import XCTest
@testable import SourceReadSwift

final class ReaderPageIdentityTests: XCTestCase {
    func testKeyIsStableWhenArrayIndexChanges() {
        let before = ReaderPageIdentity(
            chapterIndex: 5,
            pageOrdinal: 2,
            firstParagraphIndex: 17,
            isPlaceholder: false
        )
        let after = ReaderPageIdentity(
            chapterIndex: 5,
            pageOrdinal: 2,
            firstParagraphIndex: 17,
            isPlaceholder: false
        )
        XCTAssertEqual(before.key, after.key)
        XCTAssertFalse(before.key.contains("id"))
    }

    func testKeySeparatesChapterOrdinalAndParagraph() {
        let base = ReaderPageIdentity(
            chapterIndex: 5,
            pageOrdinal: 1,
            firstParagraphIndex: 4,
            isPlaceholder: false
        )
        let otherChapter = ReaderPageIdentity(
            chapterIndex: 6,
            pageOrdinal: 1,
            firstParagraphIndex: 4,
            isPlaceholder: false
        )
        let otherOrdinal = ReaderPageIdentity(
            chapterIndex: 5,
            pageOrdinal: 2,
            firstParagraphIndex: 4,
            isPlaceholder: false
        )
        let otherParagraph = ReaderPageIdentity(
            chapterIndex: 5,
            pageOrdinal: 1,
            firstParagraphIndex: 5,
            isPlaceholder: false
        )
        XCTAssertNotEqual(base.key, otherChapter.key)
        XCTAssertNotEqual(base.key, otherOrdinal.key)
        XCTAssertNotEqual(base.key, otherParagraph.key)
    }

    func testFirstIndexFindsPageAfterWindowInsert() {
        let target = ReaderPageIdentity(
            chapterIndex: 5,
            pageOrdinal: 0,
            firstParagraphIndex: 0,
            isPlaceholder: false
        )
        let pages = [
            makePage(id: 0, chapter: 3, ordinal: 0, paragraph: 0),
            makePage(id: 1, chapter: 4, ordinal: 0, paragraph: 0),
            makePage(id: 2, chapter: 5, ordinal: 0, paragraph: 0),
            makePage(id: 3, chapter: 5, ordinal: 1, paragraph: 12)
        ]
        XCTAssertEqual(ReaderPageIdentity.firstIndex(of: target.key, in: pages), 2)
    }

    private func makePage(id: Int, chapter: Int, ordinal: Int, paragraph: Int) -> ReaderPageBlock {
        ReaderPageBlock(
            id: id,
            includesTitle: false,
            paragraphs: [ReaderPageEntry(index: paragraph, text: "p\(paragraph)")],
            chapterIndex: chapter,
            pageOrdinal: ordinal
        )
    }
}

final class ReaderPageRestorationTests: XCTestCase {
    func testChapterFiveAnchorSurvivesTwoChaptersInsertedAbove() {
        // The reported regression: the reader is on chapter 5, a backward
        // prefetch inserts chapters 2 and 3 above it, and the cursor used to
        // commit the old array index, which then pointed at chapter 2.
        let anchor = ReaderChapterPosition(chapterIndex: 5, paragraphIndex: 40, pageOrdinal: 3)
        let pages = [
            makePage(id: 0, chapter: 2, ordinal: 0, paragraph: 0),
            makePage(id: 1, chapter: 2, ordinal: 1, paragraph: 9),
            makePage(id: 2, chapter: 3, ordinal: 0, paragraph: 0),
            makePage(id: 3, chapter: 5, ordinal: 0, paragraph: 0),
            makePage(id: 4, chapter: 5, ordinal: 3, paragraph: 40)
        ]

        let index = ReaderPageRestoration.index(anchor: anchor, in: pages, fallbackIndex: 1)

        XCTAssertEqual(index, 4)
        XCTAssertEqual(pages[index].chapterIndex, 5)
    }

    func testRepaginatedChapterUsesLastPageStartingAtOrBeforeAnchor() {
        let anchor = ReaderChapterPosition(chapterIndex: 7, paragraphIndex: 30)
        let pages = [
            makePage(id: 0, chapter: 7, ordinal: 0, paragraph: 0),
            makePage(id: 1, chapter: 7, ordinal: 1, paragraph: 10),
            makePage(id: 2, chapter: 7, ordinal: 2, paragraph: 20),
            makePage(id: 3, chapter: 7, ordinal: 3, paragraph: 50)
        ]

        let index = ReaderPageRestoration.index(anchor: anchor, in: pages, fallbackIndex: 0)

        XCTAssertEqual(index, 2)
    }

    func testAnchorBeforeChapterFirstParagraphLandsOnChapterFirstPage() {
        let anchor = ReaderChapterPosition(chapterIndex: 7, paragraphIndex: 0)
        let pages = [
            makePage(id: 0, chapter: 6, ordinal: 0, paragraph: 0),
            makePage(id: 1, chapter: 7, ordinal: 0, paragraph: 4),
            makePage(id: 2, chapter: 7, ordinal: 1, paragraph: 12)
        ]

        let index = ReaderPageRestoration.index(anchor: anchor, in: pages, fallbackIndex: 0)

        XCTAssertEqual(index, 1)
    }

    func testAnchorChapterMissingMovesForwardInsteadOfBackwards() {
        let anchor = ReaderChapterPosition(chapterIndex: 9, paragraphIndex: 3, pageOrdinal: 1)
        let pages = [
            makePage(id: 0, chapter: 4, ordinal: 0, paragraph: 0),
            makePage(id: 1, chapter: 5, ordinal: 0, paragraph: 0),
            makePage(id: 2, chapter: 10, ordinal: 0, paragraph: 0)
        ]

        let index = ReaderPageRestoration.index(anchor: anchor, in: pages, fallbackIndex: 1)

        XCTAssertEqual(index, 2)
        XCTAssertEqual(pages[index].chapterIndex, 10)
    }

    func testPlaceholderBoundaryAnchorResolvesToNeighbourPage() {
        let placeholder = ReaderPageBlock(
            id: 0,
            includesTitle: false,
            paragraphs: [],
            chapterIndex: 8,
            pageOrdinal: 0,
            isPlaceholder: true,
            placeholderDirection: 1
        )
        let pages = [
            makePage(id: 1, chapter: 7, ordinal: 0, paragraph: 0),
            placeholder,
            makePage(id: 2, chapter: 8, ordinal: 0, paragraph: 0)
        ]

        let anchor = ReaderChapterPosition(chapterIndex: 8, paragraphIndex: 0)
        let index = ReaderPageRestoration.index(anchor: anchor, in: pages, fallbackIndex: 0)

        XCTAssertEqual(index, 2)
    }

    func testEmptyModelReturnsZero() {
        XCTAssertEqual(ReaderPageRestoration.index(anchor: nil, in: [], fallbackIndex: 5), 0)
    }

    func testFallbackIsClampedWhenNoAnchorExists() {
        let pages = [makePage(id: 0, chapter: 1, ordinal: 0, paragraph: 0)]
        XCTAssertEqual(ReaderPageRestoration.index(anchor: nil, in: pages, fallbackIndex: 99), 0)
        XCTAssertEqual(ReaderPageRestoration.index(anchor: nil, in: pages, fallbackIndex: -3), 0)
    }

    private func makePage(id: Int, chapter: Int, ordinal: Int, paragraph: Int) -> ReaderPageBlock {
        ReaderPageBlock(
            id: id,
            includesTitle: false,
            paragraphs: [ReaderPageEntry(index: paragraph, text: "p\(paragraph)")],
            chapterIndex: chapter,
            pageOrdinal: ordinal
        )
    }
}
