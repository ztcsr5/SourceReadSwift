import XCTest
@testable import SourceReadSwift

final class ChapterTextSanitizerTests: XCTestCase {
    func testStripsHeadingRepeatedAsFirstParagraph() {
        let result = ChapterTextSanitizer.normalize(
            title: "第一章 初见",
            paragraphs: ["第一章 初见", "夜色很深。", "他推门而入。"],
            fallbackTitle: "第一章"
        )
        XCTAssertEqual(result.title, "第一章 初见")
        XCTAssertEqual(result.paragraphs, ["夜色很深。", "他推门而入。"])
        XCTAssertEqual(result.removedLeadingTitleCount, 1)
        XCTAssertFalse(result.recoveredTitleFromBody)
    }

    func testRecoversMissingTitleFromBody() {
        let result = ChapterTextSanitizer.normalize(
            title: "正文",
            paragraphs: ["第十二章 风起", "风从山谷吹来。"],
            fallbackTitle: "第 12 章"
        )
        XCTAssertEqual(result.title, "第十二章 风起")
        XCTAssertEqual(result.paragraphs, ["风从山谷吹来。"])
        XCTAssertTrue(result.recoveredTitleFromBody)
    }

    func testKeepsNormalFirstParagraph() {
        let result = ChapterTextSanitizer.normalize(
            title: "第一章 初见",
            paragraphs: ["夜色很深。", "他推门而入。"],
            fallbackTitle: "第一章"
        )
        XCTAssertEqual(result.title, "第一章 初见")
        XCTAssertEqual(result.paragraphs, ["夜色很深。", "他推门而入。"])
        XCTAssertEqual(result.removedLeadingTitleCount, 0)
    }

    func testStripsSourceIndentAndFullWidthSpaces() {
        let result = ChapterTextSanitizer.normalize(
            title: "第一章",
            paragraphs: ["\u{3000}\u{3000}第一段。", "\u{3000}第二段。"],
            fallbackTitle: "第一章"
        )
        XCTAssertEqual(result.paragraphs, ["第一段。", "第二段。"])
    }

    func testPlaceholderTitleFallsBack() {
        let result = ChapterTextSanitizer.normalize(
            title: "null",
            paragraphs: ["正文内容。"],
            fallbackTitle: "第 3 章"
        )
        XCTAssertEqual(result.title, "第 3 章")
    }

    func testRemovesRepeatedHeadingInFirstFourParagraphs() {
        let result = ChapterTextSanitizer.normalize(
            title: "第一章 初见",
            paragraphs: ["第一章 初见", "第一段。", "第一章 初见", "第二段。"],
            fallbackTitle: "第一章"
        )
        XCTAssertEqual(result.paragraphs, ["第一段。", "第二段。"])
    }

    func testMarkerOnlyTitleStillDeduplicatesLongerBodyHeading() {
        let result = ChapterTextSanitizer.normalize(
            title: "第8章",
            paragraphs: ["第8章 入城", "城门开了。"],
            fallbackTitle: "第 8 章"
        )
        XCTAssertEqual(result.title, "第8章")
        XCTAssertEqual(result.paragraphs, ["城门开了。"])
        XCTAssertEqual(result.removedLeadingTitleCount, 1)
    }

    func testDeduplicatesWhenNumeralStyleDiffers() {
        let result = ChapterTextSanitizer.normalize(
            title: "第八章 入城",
            paragraphs: ["第8章 入城", "城门开了。"],
            fallbackTitle: "第 8 章"
        )
        XCTAssertEqual(result.title, "第八章 入城")
        XCTAssertEqual(result.paragraphs, ["城门开了。"])
    }

    func testDeduplicatesBracketedBodySuffix() {
        let result = ChapterTextSanitizer.normalize(
            title: "第8章 入城",
            paragraphs: ["第8章 入城（本章完）", "城门开了。"],
            fallbackTitle: "第 8 章"
        )
        XCTAssertEqual(result.paragraphs, ["城门开了。"])
    }

    func testKeepsLongParagraphThatOnlyStartsWithHeadingWord() {
        let result = ChapterTextSanitizer.normalize(
            title: "第8章 风",
            paragraphs: ["风从山谷吹来，卷起满地落叶，夜色深得像水。", "他推门而入。"],
            fallbackTitle: "第 8 章"
        )
        XCTAssertEqual(result.paragraphs.count, 2)
        XCTAssertEqual(result.removedLeadingTitleCount, 0)
    }

    func testRecoversTitleFromNumberedHeading() {
        let result = ChapterTextSanitizer.normalize(
            title: "正文",
            paragraphs: ["1. 风起", "风从山谷吹来。"],
            fallbackTitle: "第 1 章"
        )
        XCTAssertEqual(result.title, "1. 风起")
        XCTAssertTrue(result.recoveredTitleFromBody)
        XCTAssertEqual(result.paragraphs, ["风从山谷吹来。"])
    }

    func testTitleWithTrailingMarkerIsStillDeduplicated() {
        let result = ChapterTextSanitizer.normalize(
            title: "第 8 章 入城",
            paragraphs: ["第8章 入城（求月票）", "城门开了。"],
            fallbackTitle: "第 8 章"
        )
        XCTAssertEqual(result.paragraphs, ["城门开了。"])
    }
}
