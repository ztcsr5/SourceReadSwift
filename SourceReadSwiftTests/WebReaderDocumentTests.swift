import UIKit
import XCTest
@testable import SourceReadSwift

/// Locks the WebView scroll surface's pure contracts: the flat index space the
/// reader and the document must agree on, the payload shape that carries
/// chapter titles as real elements, and the tap/typography constants that keep
/// scroll mode from regressing into the old TextKit behaviour.
final class WebReaderDocumentTests: XCTestCase {
    // MARK: - Flat index space

    func testFlatStartsReserveOneIndexForEachChapterDivider() {
        XCTAssertEqual(WebReaderFlatIndexPolicy.starts(forParagraphCounts: [3, 2]), [0, 4])
        XCTAssertEqual(WebReaderFlatIndexPolicy.totalCount(forParagraphCounts: [3, 2]), 6)
    }

    func testFlatStartsMatchChapterWindowLayout() {
        let sections = [
            ReaderChapterSection(chapterIndex: 1, title: "一", paragraphs: ["a", "b"]),
            ReaderChapterSection(chapterIndex: 2, title: "二", paragraphs: ["c"]),
            ReaderChapterSection(chapterIndex: 3, title: "三", paragraphs: ["d", "e", "f"])
        ]
        let layout = ReaderChapterWindowPolicy.layout(sections)
        let counts = sections.map { $0.paragraphs.count }
        let starts = WebReaderFlatIndexPolicy.starts(forParagraphCounts: counts)
        for (offset, section) in sections.enumerated() {
            XCTAssertEqual(
                starts[offset],
                layout.paragraphStart(chapterIndex: section.chapterIndex) ?? -1
            )
        }
        XCTAssertEqual(WebReaderFlatIndexPolicy.totalCount(forParagraphCounts: counts), layout.totalCount)
    }

    func testLoadingChapterStillOccupiesItsDividerIndex() {
        // A placeholder chapter has no paragraphs yet, but the divider slot is
        // already reserved so the window can fill in without renumbering the
        // paragraphs the reader is looking at.
        XCTAssertEqual(WebReaderFlatIndexPolicy.starts(forParagraphCounts: [4, 0, 2]), [0, 5, 6])
        XCTAssertEqual(WebReaderFlatIndexPolicy.totalCount(forParagraphCounts: [4, 0, 2]), 8)
    }

    // MARK: - Content payload

    func testPayloadGivesEveryChapterItsOwnTitleAndSequentialParagraphs() throws {
        let sections = [
            WebReaderSection(chapterIndex: 0, title: "第一章", paragraphs: ["甲", "乙"]),
            WebReaderSection(chapterIndex: 1, title: "第二章", paragraphs: ["丙"])
        ]
        let payload = WebReaderContentPayloadBuilder.payload(sections: sections, showChapterEndBadge: false)
        let encoded = try XCTUnwrap(payload["sections"] as? [[String: Any]])
        XCTAssertEqual(encoded.count, 2)

        let first = encoded[0]
        XCTAssertEqual(first["first"] as? Bool, true)
        XCTAssertEqual(first["start"] as? Int, 0)
        XCTAssertEqual(first["titleFlat"] as? Int, 0)
        XCTAssertEqual(first["title"] as? String, "第一章")

        let second = encoded[1]
        XCTAssertEqual(second["first"] as? Bool, false)
        XCTAssertEqual(second["start"] as? Int, 3)
        XCTAssertEqual(second["titleFlat"] as? Int, 2)
        XCTAssertEqual(second["key"] as? String, "c1")

        let paragraphs = try XCTUnwrap(second["paragraphs"] as? [[String: Any]])
        XCTAssertEqual(paragraphs.first?["flat"] as? Int, 3)
        XCTAssertEqual(paragraphs.first?["local"] as? Int, 0)
        XCTAssertEqual(paragraphs.first?["text"] as? String, "丙")
        XCTAssertEqual(payload["total"] as? Int, 4)
    }

    func testPayloadSplitsIllustrationsAndStripsLegacyDividerDecoration() throws {
        let sections = [
            WebReaderSection(
                chapterIndex: 0,
                title: "第一章",
                paragraphs: [
                    "正文",
                    "[img]https://cdn.example.test/a.jpg[/img]",
                    "——— 第二章 ———"
                ]
            )
        ]
        let payload = WebReaderContentPayloadBuilder.payload(sections: sections, showChapterEndBadge: true)
        let encoded = try XCTUnwrap(payload["sections"] as? [[String: Any]])
        let paragraphs = try XCTUnwrap(encoded.first?["paragraphs"] as? [[String: Any]])

        XCTAssertEqual(paragraphs[0]["text"] as? String, "正文")
        let imageSource = try XCTUnwrap(paragraphs[1]["image"] as? String)
        XCTAssertTrue(imageSource.hasPrefix("readerimg://i/"))
        XCTAssertEqual(
            WebReaderImageScheme.originalURL(from: imageSource)?.absoluteString,
            "https://cdn.example.test/a.jpg"
        )
        XCTAssertNil(paragraphs[1]["text"])
        XCTAssertEqual(paragraphs[2]["text"] as? String, "第二章")
        XCTAssertEqual(encoded.first?["end"] as? Bool, true)
    }

    func testLoadingSectionAdvertisesItsPlaceholder() throws {
        let sections = [WebReaderSection(chapterIndex: 0, title: "空", paragraphs: [], isReady: false)]
        let payload = WebReaderContentPayloadBuilder.payload(sections: sections, showChapterEndBadge: false)
        let encoded = try XCTUnwrap(payload["sections"] as? [[String: Any]])
        XCTAssertEqual(encoded.first?["loading"] as? Bool, true)
    }

    // MARK: - Typography

    func testTitleIsVisiblyLargerThanBodyText() {
        XCTAssertGreaterThan(WebReaderStylePayload.titleSize(fontSize: 17), 17)
        XCTAssertGreaterThanOrEqual(WebReaderStylePayload.titleSize(fontSize: 17), 17 * 1.25)
        XCTAssertGreaterThan(WebReaderStylePayload.titleSize(fontSize: 24), 24)
    }

    func testLineHeightGrowsWithExtraLineSpacing() {
        XCTAssertEqual(WebReaderStylePayload.lineHeight(fontSize: 20, extraLineSpacing: 0), 1.0, accuracy: 0.0001)
        XCTAssertEqual(WebReaderStylePayload.lineHeight(fontSize: 20, extraLineSpacing: 6), 1.3, accuracy: 0.0001)
        XCTAssertEqual(WebReaderStylePayload.lineHeight(fontSize: 0, extraLineSpacing: 6), 1.6, accuracy: 0.0001)
    }

    func testFontFamilyMapsToInstalledCSSStacks() {
        XCTAssertTrue(ReaderFontFamily.songti.webCSSFamily.contains("Songti SC"))
        XCTAssertTrue(ReaderFontFamily.kaiti.webCSSFamily.contains("Kaiti SC"))
        XCTAssertTrue(ReaderFontFamily.system.webCSSFamily.contains("-apple-system"))
        XCTAssertEqual(ReaderFontFamily.bold.webCSSWeight, 600)
        XCTAssertEqual(ReaderFontFamily.light.webCSSWeight, 300)
    }

    func testStylePayloadCarriesThemeColoursAndInsets() throws {
        let style = WebReaderStylePayload.make(
            fontFamily: .system,
            fontSize: 20,
            lineSpacing: 6,
            pagePadding: 22,
            letterSpacing: 0.5,
            paragraphSpacing: 14,
            paragraphIndent: 40,
            titleSpacing: 18,
            footerHeight: 34,
            topInset: 56,
            textColor: UIColor(red: 1, green: 0, blue: 0, alpha: 1),
            surfaceColor: UIColor(white: 0.1, alpha: 1),
            highlightColor: UIColor(red: 0, green: 0, blue: 1, alpha: 0.2),
            accentColor: UIColor(red: 0, green: 1, blue: 0, alpha: 1),
            selectable: false
        )
        XCTAssertEqual(style.topInset, 56)
        XCTAssertEqual(style.sidePadding, 22)
        XCTAssertEqual(style.titleSize, 26.0, accuracy: 0.0001)
        XCTAssertEqual(style.lineHeight, 1.3, accuracy: 0.0001)
        XCTAssertEqual(style.textColor, "#FF0000FF")
        XCTAssertEqual(style.accentColor, "#00FF00FF")
        XCTAssertEqual(style.selectable, false)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(style.jsonObject))
    }

    // MARK: - Bridge safety

    func testJavaScriptLiteralEscapesQuoteBackslashAndLineBreaks() {
        let literal = WebReaderJavaScriptLiteral.string("a\"b\\c\nd\re")
        XCTAssertEqual(literal, "\"a\\\"b\\\\c\\nd\\re\"")
        XCTAssertTrue(WebReaderJavaScriptLiteral.string("段落").hasPrefix("\""))
    }

    func testImageSchemeRoundTripsEncodedSource() {
        let url = URL(string: "https://img.example.test/chapter-1.png?x=1&y=2")!
        let source = WebReaderImageScheme.source(for: url)
        XCTAssertTrue(source.hasPrefix("readerimg://i/"))
        XCTAssertFalse(source.contains("="))
        XCTAssertEqual(WebReaderImageScheme.originalURL(from: source), url)
    }

    // MARK: - Document shell

    func testShellDeclaresTitleStyleAndTapBridge() {
        let shell = WebReaderHTML.shell
        XCTAssertTrue(shell.contains(".chapter-title"))
        XCTAssertTrue(shell.contains("--title-size"))
        XCTAssertTrue(shell.contains("border-left: 3px solid var(--accent)"))
        XCTAssertTrue(shell.contains("pointerdown"))
        XCTAssertTrue(shell.contains("window.__reader"))
        XCTAssertTrue(shell.contains("data-flat"))
        XCTAssertTrue(shell.contains("setContent"))
        XCTAssertTrue(shell.contains("replaceChildren"))
    }

    func testShellCanResetToDocumentTop() {
        // 换书复用 WKWebView 时必须能回到顶部，否则上一本的滚动位置会带进来。
        let shell = WebReaderHTML.shell
        XCTAssertTrue(shell.contains("resetScroll"))
        XCTAssertTrue(shell.contains("window.scrollTo(0, 0)"))
    }

    func testShellFiltersAccidentalTaps() {
        let shell = WebReaderHTML.shell
        // 位移 / 时长 / 惯性三道阈值，缺一条就会把滑动判成点击。
        XCTAssertTrue(shell.contains("dx > 10"))
        XCTAssertTrue(shell.contains("held > 320"))
        XCTAssertTrue(shell.contains("state.lastScrollAt"))
        XCTAssertTrue(shell.contains("isCollapsed"))
    }
}
