import XCTest
@testable import SourceReadSwift

final class LocalTxtSmartDividerTests: XCTestCase {
    func testVolumeAndChapterGrouping() {
        let text = """
        第一卷 九州风雷
        第一章 潜龙勿用
        江水奔流不息。
        天色渐晚。
        第二章 见龙在田
        群山耸立在远方。
        第二卷 问鼎天下
        第三章 或跃在渊
        大风起兮云飞扬。
        """

        let divider = LocalTxtSmartDivider()
        let book = divider.divide(text: text, fileName: "Dragon.txt")

        XCTAssertEqual(book.title, "Dragon")
        XCTAssertEqual(book.chapters.count, 3)
        XCTAssertEqual(book.chapters[0].title, "第一卷 九州风雷 第一章 潜龙勿用")
        XCTAssertEqual(book.chapters[0].paragraphs, ["江水奔流不息。", "天色渐晚。"])
        XCTAssertEqual(book.chapters[1].title, "第一卷 九州风雷 第二章 见龙在田")
        XCTAssertEqual(book.chapters[1].paragraphs, ["群山耸立在远方。"])
        XCTAssertEqual(book.chapters[2].title, "第二卷 问鼎天下 第三章 或跃在渊")
        XCTAssertEqual(book.chapters[2].paragraphs, ["大风起兮云飞扬。"])
    }

    func testWesternChapterFormatting() {
        let text = """
        Chapter 1 The Arrival
        The ship sailed into the mist.
        Chapter 2 Into the Woods
        Branches snapped in the dark.
        """

        let divider = LocalTxtSmartDivider(mode: .western)
        let book = divider.divide(text: text, fileName: "Adventure.txt")

        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].title, "Chapter 1 The Arrival")
        XCTAssertEqual(book.chapters[1].title, "Chapter 2 Into the Woods")
    }

    func testCustomRegexPatternOverride() {
        let text = """
        §1 绪论
        这是序言内容。
        §2 核心原理
        这是正文内容。
        """

        let divider = LocalTxtSmartDivider(mode: .custom(#"^§\d+.*$"#))
        let book = divider.divide(text: text, fileName: "Thesis.txt")

        XCTAssertEqual(book.chapters.count, 2)
        XCTAssertEqual(book.chapters[0].title, "§1 绪论")
        XCTAssertEqual(book.chapters[1].title, "§2 核心原理")
    }

    func testSpecialSymbolsChapterHeadings() {
        let divider = LocalTxtSmartDivider()
        XCTAssertTrue(divider.isChapterHeading("【第一章】 归来的英雄"))
        XCTAssertTrue(divider.isChapterHeading("〔第3回〕 降魔演武"))
        XCTAssertTrue(divider.isChapterHeading("序章 远古的召唤"))
        XCTAssertTrue(divider.isChapterHeading("楔子"))
        XCTAssertTrue(divider.isChapterHeading("番外篇 往事如烟"))
        XCTAssertTrue(divider.isChapterHeading("终章 黎明的序曲"))
        XCTAssertFalse(divider.isChapterHeading("今天天气晴朗，阳光洒满了整个大地，读者正在享受阅读。"))
    }

    func testChunkingForLongTextWithoutHeadings() {
        var lines: [String] = []
        for i in 1...150 {
            lines.append("这是第 \(i) 行普通正文，没有任何章节标题标记。")
        }
        let text = lines.joined(separator: "\n")
        let divider = LocalTxtSmartDivider()
        let book = divider.divide(text: text, fileName: "RawStory.txt")

        XCTAssertGreaterThan(book.chapters.count, 1)
        XCTAssertEqual(book.chapters[0].title, "第 1 部分")
        XCTAssertEqual(book.chapters[1].title, "第 2 部分")
    }
}
