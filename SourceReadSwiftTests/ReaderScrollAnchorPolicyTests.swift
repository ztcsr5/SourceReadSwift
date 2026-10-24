import XCTest
@testable import SourceReadSwift

final class ReaderScrollAnchorPolicyTests: XCTestCase {
    func testParagraphShiftHandlesPrependAppendAndTrim() {
        XCTAssertEqual(
            ReaderScrollAnchorPolicy.paragraphShift(old: ["five"], new: ["four", "five", "six"]),
            1
        )
        XCTAssertEqual(
            ReaderScrollAnchorPolicy.paragraphShift(
                old: ["two", "three", "four", "five", "six"],
                new: ["three", "four", "five", "six", "seven"]
            ),
            -1
        )
        XCTAssertEqual(
            ReaderScrollAnchorPolicy.paragraphShift(
                old: ["zero", "one", "two", "three", "four"],
                new: ["one", "two", "three"]
            ),
            -1
        )
        XCTAssertEqual(
            ReaderScrollAnchorPolicy.paragraphShift(old: ["a", "b"], new: ["a", "b", "c"]),
            0
        )
        XCTAssertNil(ReaderScrollAnchorPolicy.paragraphShift(old: [], new: ["a"]))
        XCTAssertNil(ReaderScrollAnchorPolicy.paragraphShift(old: ["a", "b"], new: ["x", "y"]))
    }

    func testAnchorResolvesParagraphAndCharacterOffset() {
        let ranges = [NSRange(location: 0, length: 10), NSRange(location: 11, length: 20)]
        let anchor = ReaderScrollAnchorPolicy.anchor(
            paragraphRanges: ranges,
            characterIndex: 16,
            lineProgress: 0.5
        )
        XCTAssertEqual(anchor?.paragraphIndex, 1)
        XCTAssertEqual(anchor?.characterOffset, 5)
        XCTAssertEqual(anchor?.lineProgress, 0.5)
    }

    func testAnchorAttributesSeparatorToPreviousParagraph() {
        let ranges = [NSRange(location: 0, length: 10), NSRange(location: 11, length: 20)]
        let anchor = ReaderScrollAnchorPolicy.anchor(
            paragraphRanges: ranges,
            characterIndex: 10,
            lineProgress: 0
        )
        XCTAssertEqual(anchor?.paragraphIndex, 0)
        XCTAssertEqual(anchor?.characterOffset, 9)
    }

    func testImageParagraphAnchorKeepsSingleAttachmentOffset() {
        let ranges = [NSRange(location: 0, length: 1)]
        let anchor = ReaderScrollAnchorPolicy.anchor(
            paragraphRanges: ranges,
            characterIndex: 0,
            lineProgress: 1.4
        )
        XCTAssertEqual(anchor?.paragraphIndex, 0)
        XCTAssertEqual(anchor?.characterOffset, 0)
        XCTAssertEqual(anchor?.lineProgress, 1)
    }

    func testCharacterIndexUsesRebuiltRanges() {
        let oldRanges = [NSRange(location: 0, length: 10), NSRange(location: 11, length: 5)]
        let anchor = ReaderScrollAnchorPolicy.anchor(
            paragraphRanges: oldRanges,
            characterIndex: 12,
            lineProgress: 0.25
        )
        let rebuilt = [NSRange(location: 0, length: 30), NSRange(location: 31, length: 5)]
        XCTAssertEqual(anchor.flatMap { ReaderScrollAnchorPolicy.characterIndex(for: $0, in: rebuilt) }, 32)
    }

    func testAnchorClampsOutOfBoundsInput() {
        let ranges = [NSRange(location: 5, length: 3)]
        let anchor = ReaderScrollAnchorPolicy.anchor(
            paragraphRanges: ranges,
            characterIndex: 100,
            lineProgress: -1
        )
        XCTAssertEqual(anchor?.paragraphIndex, 0)
        XCTAssertEqual(anchor?.characterOffset, 2)
        XCTAssertEqual(anchor?.lineProgress, 0)
        XCTAssertNil(ReaderScrollAnchorPolicy.anchor(
            paragraphRanges: [],
            characterIndex: 0,
            lineProgress: 0
        ))
        XCTAssertNil(ReaderScrollAnchorPolicy.characterIndex(
            for: .init(paragraphIndex: 3, characterOffset: 0, lineProgress: 0),
            in: ranges
        ))
    }
}
