import UIKit
import XCTest
@testable import SourceReadSwift

/// build 114 回归：分页页面的「测得高度」必须落在渲染框内。
///
/// 用户反馈的「翻页模式最后一行只剩省略号 / 下一页空白」有两个来源：
/// 1. 段间距由当前段决定，而 TextKit 把段间距画在段末换行上，导致每页
///    多算或少算一行（已在 ReaderPageTextBuilder 改为由下一段决定）；
/// 2. 分页高度没有为页脚浮层留出硬边界（已在 ReaderPageGeometry 修）。
/// 这里把「切页 → 建富文本 → 量高度」跑成闭环，任何一侧回退都会失败。
final class ReaderPagedOverflowTests: XCTestCase {
    private func typography(contentHeight: CGFloat = 520) -> ReaderPageTypography {
        ReaderPageTypography(
            font: UIFont.systemFont(ofSize: 18),
            titleFont: UIFont.boldSystemFont(ofSize: 22),
            lineSpacing: 6,
            letterSpacing: 0.35,
            paragraphSpacing: 10,
            firstLineIndent: 36,
            titleSpacing: 8,
            contentWidth: 348,
            contentHeight: contentHeight
        )
    }

    private func builderStyle(_ typography: ReaderPageTypography) -> ReaderPageTextBuilder.Style {
        ReaderPageTextBuilder.Style(
            bodyFont: typography.font,
            titleFont: typography.titleFont,
            textColor: .label,
            highlightColor: UIColor.systemBlue.withAlphaComponent(0.2),
            lineSpacing: typography.lineSpacing,
            letterSpacing: typography.letterSpacing,
            paragraphSpacing: typography.paragraphSpacing,
            titleSpacing: typography.titleSpacing
        )
    }

    private func context(_ typography: ReaderPageTypography) -> ReaderChapterPaginationContext {
        ReaderChapterPaginationContext(
            typography: typography,
            titleTypography: typography,
            chromeLayout: .header,
            imageStyle: .standard,
            viewportHeight: 844,
            pagePadding: 21,
            footerHeight: 14,
            traditionalChinese: false
        )
    }

    private func measuredHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        return manager.usedRect(for: container).height
    }

    func testEveryPaginatedPageFitsItsRenderedBox() {
        let typography = typography()
        let paragraph = String(repeating: "这一段用来撑满分页高度，标点要正常收在行尾。", count: 24)
        let paragraphs = (0..<9).map { "第\($0 + 1)段。" + paragraph }
        let pages = ReaderChapterPaginator.paginate(
            chapterIndex: 0,
            title: "第一章 测试",
            paragraphs: paragraphs,
            context: context(typography)
        )

        XCTAssertGreaterThan(pages.count, 1, "fixture must span several pages")
        XCTAssertFalse(pages.last?.paragraphs.isEmpty ?? true, "a trailing empty page is unreachable")
        let style = builderStyle(typography)

        for page in pages {
            let built = ReaderPageTextBuilder.make(
                title: nil,
                paragraphs: page.paragraphs.map {
                    .init(text: $0.text, isContinuation: $0.isContinuation, isHighlighted: false)
                },
                style: style
            )
            let height = measuredHeight(built, width: typography.contentWidth)
            XCTAssertLessThanOrEqual(
                height,
                typography.contentHeight + 1.5,
                "page \(page.pageOrdinal + 1)/\(pages.count) measures \(height)pt, box is \(typography.contentHeight)pt"
            )
        }
    }

    /// 段间距归属于「段末换行」，所以由下一段决定：
    /// 下一段是续页 chunk（同一段被切开）→ 0；下一段是新段 → paragraphSpacing。
    func testParagraphSpacingIsDecidedByTheFollowingParagraph() {
        let style = builderStyle(typography())
        let result = ReaderPageTextBuilder.make(
            title: nil,
            paragraphs: [
                .init(text: "　　第一段。", isContinuation: false, isHighlighted: false),
                .init(text: "续页开头，同一段的后半截。", isContinuation: true, isHighlighted: false),
                .init(text: "　　第三段。", isContinuation: false, isHighlighted: false)
            ],
            style: style
        )

        func spacing(at location: Int) -> CGFloat {
            (result.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?
                .paragraphSpacing ?? -1
        }

        let ns = result.string as NSString
        XCTAssertEqual(spacing(at: ns.range(of: "第一段").location), 0, accuracy: 0.01)
        XCTAssertEqual(spacing(at: ns.range(of: "续页开头").location), max(0, style.paragraphSpacing - style.lineSpacing), accuracy: 0.01)
    }
}