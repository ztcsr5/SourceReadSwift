import XCTest
import UIKit
@testable import SourceReadSwift

final class ReaderPageLayoutEngineTests: XCTestCase {
    private func typography(
        width: CGFloat = 320,
        fontSize: CGFloat = 19,
        contentHeight: CGFloat = 600
    ) -> ReaderPageTypography {
        ReaderPageTypography(
            font: UIFont.systemFont(ofSize: fontSize),
            titleFont: UIFont.boldSystemFont(ofSize: fontSize + 8),
            lineSpacing: 8,
            letterSpacing: 0.5,
            paragraphSpacing: 12,
            firstLineIndent: fontSize * 2,
            titleSpacing: 10,
            contentWidth: width,
            contentHeight: contentHeight
        )
    }

    // MARK: - First-line indent

    func testDisplayTextConvertsPointIndentToIdeographicSpaces() {
        let display = ReaderPageLayoutEngine.displayText("正文", fontSize: 19, indent: 38)
        XCTAssertEqual(display, "\u{3000}\u{3000}正文")
        XCTAssertEqual(display.utf16.count, "正文".utf16.count + 2)
    }

    func testDisplayTextLeavesTextUntouchedWithoutIndent() {
        XCTAssertEqual(ReaderPageLayoutEngine.displayText("正文", fontSize: 19, indent: 0), "正文")
        XCTAssertEqual(ReaderPageLayoutEngine.displayText("正文", fontSize: 0, indent: 38), "正文")
        XCTAssertEqual(ReaderPageLayoutEngine.displayText("", fontSize: 19, indent: 38), "")
    }

    func testTopInsetIsSharedAcrossReaderSurfaces() {
        XCTAssertEqual(ReaderPageLayoutEngine.minimumTopInset(pagePadding: 20, safeTop: 0), 20)
        XCTAssertEqual(ReaderPageLayoutEngine.minimumTopInset(pagePadding: 48, safeTop: 0), 48)
        XCTAssertEqual(ReaderPageLayoutEngine.minimumTopInset(pagePadding: 60, safeTop: 0), 60)
        XCTAssertEqual(ReaderPageLayoutEngine.minimumTopInset(pagePadding: 20, safeTop: 59), 59 + 5)
    }

    // MARK: - Measurement

    func testEmptyParagraphMeasuresZero() {
        XCTAssertEqual(ReaderPageLayoutEngine.measureHeight("", typography: typography()), 0)
    }

    func testNarrowColumnMeasuresTallerThanWideColumn() {
        let text = String(repeating: "这是一段用于验证分页测量的中文正文。", count: 12)
        let narrow = ReaderPageLayoutEngine.measureHeight(text, typography: typography(width: 180))
        let wide = ReaderPageLayoutEngine.measureHeight(text, typography: typography(width: 360))
        XCTAssertGreaterThan(narrow, wide)
        XCTAssertGreaterThan(wide, 0)
    }

    func testLargerFontMeasuresTaller() {
        let text = String(repeating: "字号变化必须改变分页结果。", count: 20)
        let small = ReaderPageLayoutEngine.measureHeight(text, typography: typography(fontSize: 15))
        let large = ReaderPageLayoutEngine.measureHeight(text, typography: typography(fontSize: 25))
        XCTAssertGreaterThan(large, small)
    }

    func testMultiLineParagraphIsTallerThanSingleLine() {
        let single = ReaderPageLayoutEngine.measureHeight("一行字。", typography: typography())
        let multi = ReaderPageLayoutEngine.measureHeight(
            String(repeating: "这是一段会折行的正文。", count: 6),
            typography: typography()
        )
        XCTAssertGreaterThan(multi, single)
    }

    func testMeasureHeightAddsLineSpacingOncePerInterLineGap() {
        let single = ReaderPageLayoutEngine.measureHeight("一行字。", typography: typography())
        let twoLines = ReaderPageLayoutEngine.measureHeight("第一行\n第二行", typography: typography())
        XCTAssertEqual(twoLines, single * 2 + 8, accuracy: 1.5)
    }

    // MARK: - Splitting

    func testShortParagraphIsNotSplit() {
        let chunks = ReaderPageLayoutEngine.split(
            "短句。",
            firstPageHeight: 300,
            fullPageHeight: 600,
            typography: typography()
        )
        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks.first?.text, "短句。")
    }

    func testSplitReconstructsOriginalText() {
        let original = String(repeating: "第一章的长段落需要在真实行边界切开，不能丢字也不能重复。", count: 40)
        let chunks = ReaderPageLayoutEngine.split(
            original,
            firstPageHeight: 220,
            fullPageHeight: 600,
            typography: typography()
        )
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertEqual(chunks.map { $0.text }.joined(), original)
    }

    func testEveryChunkFitsItsPageBudget() {
        let original = String(repeating: "分页后的每一块都必须能在固定页面内完整绘制。", count: 50)
        let firstBudget: CGFloat = 200
        let fullBudget: CGFloat = 600
        let chunks = ReaderPageLayoutEngine.split(
            original,
            firstPageHeight: firstBudget,
            fullPageHeight: fullBudget,
            typography: typography()
        )
        XCTAssertGreaterThan(chunks.count, 2)
        for (index, chunk) in chunks.enumerated() {
            let budget = index == 0 ? firstBudget : fullBudget
            XCTAssertLessThanOrEqual(chunk.height, budget + 1, "chunk \(index) exceeded budget")
            let measured = ReaderPageLayoutEngine.measureHeight(chunk.text, typography: typography())
            XCTAssertEqual(chunk.height, measured, accuracy: 0.5)
        }
    }

    func testChunksStartAtLineBoundariesWithoutLeadingWhitespace() {
        let original = String(repeating: "行边界切分不能从半个字开始。", count: 60)
        let chunks = ReaderPageLayoutEngine.split(
            original,
            firstPageHeight: 180,
            fullPageHeight: 520,
            typography: typography()
        )
        for chunk in chunks.dropFirst() {
            XCTAssertFalse(chunk.text.hasPrefix(" "), "chunk starts with a space")
            XCTAssertFalse(chunk.text.hasPrefix("\n"), "chunk starts with a newline")
        }
    }

    func testEmptyParagraphProducesNoChunks() {
        XCTAssertTrue(
            ReaderPageLayoutEngine.split(
                "",
                firstPageHeight: 200,
                fullPageHeight: 600,
                typography: typography()
            ).isEmpty
        )
    }
}