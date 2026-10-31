import UIKit
import XCTest
@testable import SourceReadSwift

final class ReaderPageTextBuilderTests: XCTestCase {
    private func makeStyle() -> ReaderPageTextBuilder.Style {
        ReaderPageTextBuilder.Style(
            bodyFont: UIFont.systemFont(ofSize: 18),
            titleFont: UIFont.boldSystemFont(ofSize: 26),
            textColor: .label,
            highlightColor: UIColor.systemBlue.withAlphaComponent(0.2),
            lineSpacing: 8,
            letterSpacing: 0.5,
            paragraphSpacing: 10,
            titleSpacing: 12
        )
    }

    private func paragraphStyle(_ text: NSAttributedString, at location: Int) -> NSParagraphStyle? {
        text.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle
    }

    func testFullLinesAreJustifiedWithoutAddingHeadIndent() {
        let result = ReaderPageTextBuilder.make(
            title: nil,
            paragraphs: [
                .init(text: "　　第一段正文内容。", isContinuation: false, isHighlighted: false),
                .init(text: "　　第二段正文内容。", isContinuation: false, isHighlighted: false)
            ],
            style: makeStyle()
        )

        let style = paragraphStyle(result, at: 0)
        XCTAssertEqual(style?.alignment, .justified)
        XCTAssertEqual(style?.firstLineHeadIndent ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(style?.headIndent ?? -1, 0, accuracy: 0.01)
        // Effective spacing = max(0, paragraphSpacing(10) - lineSpacing(8)) = 2
        XCTAssertEqual(style?.paragraphSpacing ?? -1, 2, accuracy: 0.01)
    }

    func testContinuationChunkSpacingBelongsToTheTerminatingNewline() {
        let result = ReaderPageTextBuilder.make(
            title: nil,
            paragraphs: [
                .init(text: "续页开头", isContinuation: true, isHighlighted: false),
                .init(text: "最后一段", isContinuation: false, isHighlighted: false)
            ],
            style: makeStyle()
        )

        // 段间距画在本段末尾的换行上：续页 chunk 后面还有新段时必须保留
        // paragraphSpacing（分页器在 currentEntries 非空时就是这么加间距的），
        // 只有整页最后一段才归零。
        let first = paragraphStyle(result, at: 0)
        // With lineSpacing=8 and paragraphSpacing=10, the effective paragraphSpacing applied
        // to TextKit 1 is max(0, 10 - 8) = 2, so that lineSpacing (8) + paragraphSpacing (2) = 10
        XCTAssertEqual(first?.paragraphSpacing ?? -1, 2, accuracy: 0.01)
        let lastLocation = result.string.utf16.count - 2
        XCTAssertEqual(paragraphStyle(result, at: lastLocation)?.paragraphSpacing ?? -1, 0, accuracy: 0.01)
    }

    func testTitleUsesLargerFontAndTitleSpacing() {
        let title = "第一章 标题"
        let result = ReaderPageTextBuilder.make(
            title: title,
            paragraphs: [
                .init(text: "　　正文。", isContinuation: false, isHighlighted: false)
            ],
            style: makeStyle()
        )

        let titleStyle = paragraphStyle(result, at: 0)
        let titleFont = result.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        let bodyFont = result.attribute(.font, at: title.utf16.count + 1, effectiveRange: nil) as? UIFont
        XCTAssertEqual(titleStyle?.alignment, .natural)
        XCTAssertEqual(titleStyle?.paragraphSpacing ?? -1, 12, accuracy: 0.01)
        XCTAssertGreaterThan(titleFont?.pointSize ?? 0, bodyFont?.pointSize ?? 0)
    }

    func testBodyAndTitleUsePushOutLineBreakStrategy() {
        let title = "第一章 标题"
        let result = ReaderPageTextBuilder.make(
            title: title,
            paragraphs: [
                .init(text: "　　正文内容，标点不应落到行首。", isContinuation: false, isHighlighted: false)
            ],
            style: makeStyle()
        )

        XCTAssertEqual(
            paragraphStyle(result, at: 0)?.lineBreakStrategy,
            .pushOut,
            "title preserves the shared orphan-word avoidance strategy"
        )
        XCTAssertEqual(
            paragraphStyle(result, at: title.utf16.count + 1)?.lineBreakStrategy,
            .pushOut,
            "body must measure and render with the paginator's strategy"
        )
    }

    func testMinimumLineHeightMatchesEachFontWithoutCappingTallerGlyphs() {
        let style = makeStyle()
        let title = "第一章 标题"
        let result = ReaderPageTextBuilder.make(
            title: title,
            paragraphs: [
                .init(text: "　　正文。", isContinuation: false, isHighlighted: false)
            ],
            style: style
        )

        // UITextView uses the font's natural line height even for all-CJK lines.
        // Standalone TextKit pagination must use the same floor, while leaving
        // the maximum unset so taller fallback/emoji glyphs can still fit.
        let titleStyle = paragraphStyle(result, at: 0)
        let bodyStyle = paragraphStyle(result, at: title.utf16.count + 1)
        XCTAssertEqual(titleStyle?.minimumLineHeight ?? -1, style.titleFont.lineHeight, accuracy: 0.01)
        XCTAssertEqual(bodyStyle?.minimumLineHeight ?? -1, style.bodyFont.lineHeight, accuracy: 0.01)
        XCTAssertEqual(titleStyle?.maximumLineHeight ?? -1, 0, accuracy: 0.01)
        XCTAssertEqual(bodyStyle?.maximumLineHeight ?? -1, 0, accuracy: 0.01)
    }

    func testCJKPunctuationIsCompressedLikeIOS17() {
        // iOS 16 keeps the full em advance for `，`/`。` even though the glyph
        // paints half of it. The builder trims the trailing blank so a line
        // that ends with a comma reaches the right margin on both OS versions.
        let style = makeStyle()
        let text = "　　他说，好。"
        let result = ReaderPageTextBuilder.make(
            title: nil,
            paragraphs: [.init(text: text, isContinuation: false, isHighlighted: false)],
            style: style
        )
        let ns = text as NSString
        let em = style.bodyFont.pointSize

        func kern(at location: Int) -> CGFloat {
            (result.attribute(.kern, at: location, effectiveRange: nil) as? CGFloat) ?? 0
        }

        XCTAssertEqual(kern(at: ns.range(of: "，").location), style.letterSpacing - 0.5 * em, accuracy: 0.01)
        XCTAssertEqual(kern(at: ns.range(of: "。").location), style.letterSpacing - 0.5 * em, accuracy: 0.01)
        XCTAssertEqual(kern(at: ns.range(of: "说").location), style.letterSpacing, accuracy: 0.01)
    }

    func testTitleIsNotPunctuationCompressed() {
        let style = makeStyle()
        let title = "第一章，标题。"
        let result = ReaderPageTextBuilder.make(
            title: title,
            paragraphs: [.init(text: "　　正文。", isContinuation: false, isHighlighted: false)],
            style: style
        )
        let comma = (title as NSString).range(of: "，").location
        let kern = (result.attribute(.kern, at: comma, effectiveRange: nil) as? CGFloat) ?? .nan
        XCTAssertTrue(kern.isNaN || abs(kern) < 0.01, "titles keep their natural advance")
    }

    func testHighlightAddsBackground() {
        let result = ReaderPageTextBuilder.make(
            title: nil,
            paragraphs: [
                .init(text: "高亮段落", isContinuation: false, isHighlighted: true)
            ],
            style: makeStyle()
        )

        XCTAssertNotNil(result.attribute(.backgroundColor, at: 0, effectiveRange: nil))
    }
}
