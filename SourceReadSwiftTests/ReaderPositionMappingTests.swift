import XCTest
@testable import SourceReadSwift

final class ReaderPositionMappingTests: XCTestCase {
    func testEmptyContentAlwaysResolvesToZero() {
        let mapping = ReaderPositionMapping(paragraphCount: 0, pageFirstParagraphs: [])
        XCTAssertEqual(mapping.clampParagraph(-20), 0)
        XCTAssertEqual(mapping.page(containingParagraph: 99), 0)
        XCTAssertEqual(mapping.paragraph(forPage: 4), 0)
    }

    func testParagraphAndPageMappingClampsAndPreservesLocation() {
        let mapping = ReaderPositionMapping(paragraphCount: 10, pageFirstParagraphs: [0, 3, 7])
        XCTAssertEqual(mapping.page(containingParagraph: 0), 0)
        XCTAssertEqual(mapping.page(containingParagraph: 2), 0)
        XCTAssertEqual(mapping.page(containingParagraph: 3), 1)
        XCTAssertEqual(mapping.page(containingParagraph: 9), 2)
        XCTAssertEqual(mapping.page(containingParagraph: 999), 2)
        XCTAssertEqual(mapping.paragraph(forPage: 1), 3)
        XCTAssertEqual(mapping.paragraph(forPage: -1), 0)
        XCTAssertEqual(mapping.paragraph(forPage: 99), 7)
    }

    func testPageLookupHandlesLargeMonotonicMappings() {
        let starts = stride(from: 0, to: 10_000, by: 5).map { $0 }
        let mapping = ReaderPositionMapping(paragraphCount: 10_000, pageFirstParagraphs: starts)
        XCTAssertEqual(mapping.page(containingParagraph: 0), 0)
        XCTAssertEqual(mapping.page(containingParagraph: 4), 0)
        XCTAssertEqual(mapping.page(containingParagraph: 5_001), 1_000)
        XCTAssertEqual(mapping.page(containingParagraph: 9_999), 1_999)
    }

    func testModeSwitchUsesOneParagraphPosition() {
        let mapping = ReaderPositionMapping(paragraphCount: 12, pageFirstParagraphs: [0, 4, 8])
        let paragraph = 6
        let page = mapping.target(for: .pageTurn, paragraph: paragraph)
        XCTAssertEqual(page, 1)
        XCTAssertEqual(mapping.paragraph(for: page, mode: .pageTurn), 4)
        XCTAssertEqual(mapping.target(for: .scroll, paragraph: paragraph), paragraph)
    }

    func testPageStartsKeepTitleOnlyPagesAddressable() {
        // A leading chapter-cover page owns no paragraph. Dropping it would
        // shift every page index; it must inherit the first text page instead.
        XCTAssertEqual(
            ReaderPositionMapping.pageStarts(from: [nil, 0, 3]),
            [0, 0, 3]
        )
        // A cover page in the middle maps to the next page's paragraph.
        XCTAssertEqual(
            ReaderPositionMapping.pageStarts(from: [0, nil, 3]),
            [0, 3, 3]
        )
        // Empty chapter: the single page still resolves to paragraph 0.
        XCTAssertEqual(ReaderPositionMapping.pageStarts(from: [nil]), [0])
    }

    func testTitleOnlyPageDoesNotShrinkReachablePageRange() {
        let starts = ReaderPositionMapping.pageStarts(from: [nil, 0, 4, 7])
        let mapping = ReaderPositionMapping(paragraphCount: 10, pageFirstParagraphs: starts)
        XCTAssertEqual(mapping.maximumPageIndex, 3)
        XCTAssertEqual(mapping.paragraph(forPage: 3), 7)
        XCTAssertEqual(mapping.page(containingParagraph: 7), 3)
    }

    func testAutomationSessionRejectsOldGenerationAfterRestart() {
        var session = ReaderAutomationSession()
        let first = session.startAutoScroll()
        XCTAssertTrue(session.acceptsAutoScroll(first))
        let second = session.startSpeaking()
        XCTAssertFalse(session.acceptsAutoScroll(first))
        XCTAssertTrue(session.acceptsSpeech(second))
        session.stop()
        XCTAssertFalse(session.acceptsSpeech(second))
    }
}
