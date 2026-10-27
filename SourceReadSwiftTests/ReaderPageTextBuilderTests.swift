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
        XCTAssertEqual(style?.paragraphSpacing ?? -1, 10, accuracy: 0.01)
    }

    func testContinuationAndLastParagraphDoNotAddSpacing() {
        let result = ReaderPageTextBuilder.make(
            title: nil,
            paragraphs: [
                .init(text: "续页开头", isContinuation: true, isHighlighted: false),
                .init(text: "最后一段", isContinuation: false, isHighlighted: false)
            ],
            style: makeStyle()
        )

        let first = paragraphStyle(result, at: 0)
        XCTAssertEqual(first?.paragraphSpacing ?? -1, 0, accuracy: 0.01)
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
