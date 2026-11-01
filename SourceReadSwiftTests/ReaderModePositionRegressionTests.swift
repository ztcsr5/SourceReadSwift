import SwiftUI
import WebKit
import XCTest
@testable import SourceReadSwift

final class ReaderModePositionRegressionTests: XCTestCase {
    private func pages(chapter: Int = 2) -> [ReaderPageBlock] {
        (0..<4).map { ordinal in
            ReaderPageBlock(id: ordinal, includesTitle: false,
                paragraphs: [.init(index: 0, text: "中文👩🏽‍💻AB", chunkIndex: ordinal,
                                   sourceUTF16Offset: ordinal * "中文👩🏽‍💻AB".utf16.count)],
                chapterIndex: chapter, pageOrdinal: ordinal)
        }
    }

    func testRepeatedPagedModeChangesKeepContinuationCharacterInsteadOfParagraphStart() {
        let blocks = pages()
        let mapping = ReaderPositionMapping(paragraphCount: 1, pageFirstParagraphs: [0, 0, 0, 0])
        var selected = 2
        // This is the old mode-change failure: the paragraph mapping discards
        // the continuation offset and sends every mode back to page zero.
        XCTAssertEqual(mapping.page(containingParagraph: 0), 0)
        for _ in 0..<20 {
            for mode in [ReaderMode.pageTurn, .cover, .pageCurl] {
                XCTAssertNotEqual(mode, .scroll)
                let page = blocks[selected]
                let anchor = ReaderChapterPosition(chapterIndex: page.chapterIndex,
                    paragraphIndex: page.firstParagraphIndex ?? 0, pageOrdinal: page.pageOrdinal,
                    paragraphUTF16Offset: page.paragraphs.first?.sourceUTF16Offset)
                selected = ReaderPageRestoration.index(anchor: anchor, in: blocks, fallbackIndex: 0)
                XCTAssertEqual(selected, 2, "Mode \(mode) must retain the page, not just its paragraph")
            }
        }
    }

    func testModeAnchorSurvivesInsertedPreviousChapterAndChangedPageOrdinals() {
        let old = pages()[2]
        let anchor = ReaderChapterPosition(chapterIndex: 2, paragraphIndex: 0, pageOrdinal: 2,
                                          paragraphUTF16Offset: old.paragraphs[0].sourceUTF16Offset)
        let previous = pages(chapter: 1)
        let newPages = [ReaderPageBlock(id: 4, includesTitle: false,
            paragraphs: [.init(index: 0, text: String(repeating: "中", count: 100), sourceUTF16Offset: 0)],
            chapterIndex: 2, pageOrdinal: 0)]
        let all = previous + newPages
        let index = ReaderPageRestoration.index(anchor: anchor, in: all, fallbackIndex: 2)
        XCTAssertEqual(index, 4)
        XCTAssertEqual(all[index].chapterIndex, 2)
    }

    func testExactUTF16PageBoundaryBelongsToFollowingPage() {
        let blocks = pages()
        for page in blocks {
            let anchor = ReaderChapterPosition(chapterIndex: 2, paragraphIndex: 0,
                pageOrdinal: 0, paragraphUTF16Offset: page.paragraphs[0].sourceUTF16Offset)
            XCTAssertEqual(ReaderPageRestoration.index(anchor: anchor, in: blocks, fallbackIndex: 0), page.pageOrdinal)
        }
    }

    @MainActor func testWebScrollRestoresAndReportsInsideOneLongParagraph() async throws {
        var offset = -1
        var applied = false
        let text = String(repeating: "长段正文，模式切换不能回到段首。👩🏽‍💻", count: 150)
        let fixture = WebScrollReaderView(
            sections: [WebReaderSection(chapterIndex: 0, title: "长段落", paragraphs: [text, "末段"])],
            contentFingerprint: "mode-position-regression", fontSize: 20, lineSpacing: 8,
            pagePadding: 20, letterSpacing: 0, paragraphSpacing: 12, paragraphIndent: 40,
            titleSpacing: 16, footerHeight: 12, topInset: 50, textColor: .black,
            highlightColor: .yellow, currentParagraphIndex: -1, scrollTarget: 0,
            scrollRequestKey: "restore-character-600", scrollTargetUTF16Offset: 600,
            animatedScrollDuration: 0, textSelectionEnabled: false,
            onVisibleParagraph: { _ in }, onVisiblePosition: { _, value in offset = value },
            onScrollTargetApplied: { applied = true })
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: fixture)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<150 {
            if applied && offset > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(applied, "The real WebKit document must acknowledge the character jump")
        XCTAssertGreaterThan(offset, 500, "Paragraph zero must not silently restore to its start")
        XCTAssertLessThanOrEqual(offset, 600, "The visible line should contain the requested character")
    }
}
