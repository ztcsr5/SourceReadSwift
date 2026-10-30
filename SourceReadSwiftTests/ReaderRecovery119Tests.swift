import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class ReaderRecovery119Tests: XCTestCase {
    func testMiddleParagraphChangesTheChapterRevision() {
        var section = ReaderChapterSection(chapterIndex: 0, title: "章节", paragraphs: ["开头", "旧内容", "结尾"])
        let before = section.contentRevision
        section.paragraphs[1] = "新内容"
        XCTAssertNotEqual(before, section.contentRevision)
        XCTAssertEqual(section.contentRevision, ReaderRenderRevision.chapter(title: section.title, paragraphs: section.paragraphs))
    }

    func testRenderRevisionChangesWithoutChangingLocationIdentity() {
        let a = ReaderPageBlock(id: 0, includesTitle: false, paragraphs: [.init(index: 0, text: "ABCD")], chapterIndex: 0)
        let b = ReaderPageBlock(id: 0, includesTitle: false, paragraphs: [.init(index: 0, text: "ABCDEF")], chapterIndex: 0)
        XCTAssertEqual(ReaderPageIdentity(page: a), ReaderPageIdentity(page: b))
        XCTAssertNotEqual(ReaderRenderRevision.page(a), ReaderRenderRevision.page(b))
    }

    func testCharacterAnchorWinsOverOldPageOrdinalAfterRepagination() {
        let blocks = [
            ReaderPageBlock(id: 0, includesTitle: false, paragraphs: [.init(index: 0, text: "ABCDEF", sourceUTF16Offset: 0)], chapterIndex: 2, pageOrdinal: 0),
            ReaderPageBlock(id: 1, includesTitle: false, paragraphs: [.init(index: 0, text: "GHIJKL", chunkIndex: 1, sourceUTF16Offset: 6)], chapterIndex: 2, pageOrdinal: 1)
        ]
        let anchor = ReaderChapterPosition(chapterIndex: 2, paragraphIndex: 0, pageOrdinal: 1, paragraphUTF16Offset: 4)
        XCTAssertEqual(ReaderPageRestoration.index(anchor: anchor, in: blocks, fallbackIndex: 1), 0)
    }

    func testFinalTextKitPagesFitAndConserveEveryParagraphAcrossTypographyMatrix() {
        let paragraphs = (0..<18).map { index in
            "第\(index)段：" + String(repeating: "中文标点，Mixed text 123、👩🏽‍💻🙂（对话）与段尾。", count: index % 4 + 1)
        }
        for size: CGFloat in [16, 20, 30] {
            for line: CGFloat in [0, 8, 18] {
                for gap: CGFloat in [0, 4, 16] {
                    for heading in [ReaderPageChromeLayout.header, .inline] {
                        let typography = ReaderPageTypography(
                            font: .systemFont(ofSize: size), titleFont: .boldSystemFont(ofSize: size * 1.3),
                            lineSpacing: line, letterSpacing: 0.35, paragraphSpacing: gap,
                            firstLineIndent: size * 2, titleSpacing: 12, contentWidth: 280, contentHeight: 320
                        )
                        let context = ReaderChapterPaginationContext(
                            typography: typography, titleTypography: typography, chromeLayout: heading,
                            imageStyle: .standard, viewportHeight: 568, pagePadding: 21, footerHeight: 14,
                            traditionalChinese: false
                        )
                        let pages = ReaderChapterPaginator.paginate(chapterIndex: 0, title: "第一章 精确排版与中文标题", paragraphs: paragraphs, context: context)
                        XCTAssertGreaterThan(pages.count, 1)
                        for (index, original) in paragraphs.enumerated() {
                            let entries = pages.flatMap(\.paragraphs).filter { $0.index == index }
                            let expected = ReaderPageLayoutEngine.displayText(original, fontSize: size, indent: size * 2)
                            XCTAssertEqual(entries.map(\.text).joined(), expected, "missing/repeated characters at \(size)/\(line)/\(gap)")
                            var offset = 0
                            for entry in entries {
                                XCTAssertEqual(entry.sourceUTF16Offset, offset)
                                offset += entry.text.utf16.count
                            }
                        }
                        for page in pages {
                            let text = ReaderPageTextBuilder.make(
                                title: page.includesTitle ? (page.inlineTitleText ?? page.chapterTitle) : nil,
                                paragraphs: page.paragraphs.map { .init(text: $0.text, isContinuation: $0.isContinuation, isHighlighted: false) },
                                style: ReaderPageTextBuilder.layoutStyle(typography)
                            )
                            let storage = NSTextStorage(attributedString: text)
                            let manager = NSLayoutManager()
                            let container = NSTextContainer(size: CGSize(width: typography.contentWidth, height: .greatestFiniteMagnitude))
                            container.lineFragmentPadding = 0
                            manager.addTextContainer(container)
                            storage.addLayoutManager(manager)
                            manager.ensureLayout(for: container)
                            XCTAssertLessThanOrEqual(manager.usedRect(for: container).maxY, typography.contentHeight + 0.5,
                                                     "overflow \(size)/\(line)/\(gap)/\(heading) page \(page.pageOrdinal)")
                        }
                    }
                }
            }
        }
    }

    func testPanPolicySupportsFlicksAndNeverCommitsPastBookEdges() {
        XCTAssertEqual(ReaderPanTurnPolicy.direction(translation: -15, velocity: -1000, width: 390, hasPrevious: true, hasNext: true), 1)
        XCTAssertEqual(ReaderPanTurnPolicy.direction(translation: 15, velocity: 1000, width: 390, hasPrevious: true, hasNext: true), -1)
        XCTAssertEqual(ReaderPanTurnPolicy.direction(translation: -300, velocity: -1000, width: 390, hasPrevious: true, hasNext: false), 0)
        XCTAssertEqual(ReaderPanTurnPolicy.direction(translation: 300, velocity: 1000, width: 390, hasPrevious: false, hasNext: true), 0)
        XCTAssertEqual(ReaderPanTurnPolicy.direction(translation: 2, velocity: 0, width: 390, hasPrevious: true, hasNext: true), 0)
    }
}

@MainActor
final class ReaderPanController119Tests: XCTestCase {
    private var commits: [Int] = []
    private var interactions: [Bool] = []

    private func drainMainQueue() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    private func apply(_ controller: CoverPageHostController, page: String = "p0", next: String = "placeholder", style: CoverPageTurnStyle = .cover) {
        controller.apply(
            pageIdentity: page, contentRevision: "same-layout",
            previousIdentity: "prev-\(page)", currentIdentity: page, nextIdentity: next,
            hasPrevious: true, hasNext: true,
            previous: AnyView(Color.red), current: AnyView(Color.green), next: AnyView(Color.blue),
            onCommit: { [weak self] in self?.commits.append($0) },
            onInteractionChange: { [weak self] in self?.interactions.append($0) },
            onPageContainerLayout: nil, turnStyle: style
        )
    }

    private func makeController() -> CoverPageHostController {
        let controller = CoverPageHostController()
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        controller.view.layoutIfNeeded()
        return controller
    }

    func testNeighbourArrivalRefreshesWithoutChangingCurrentPage() {
        let controller = makeController()
        apply(controller)
        apply(controller, next: "real-next")
        XCTAssertEqual(controller.visiblePageIdentity, "p0")
        XCTAssertEqual(controller.installedPageKeys[3], "real-next")
        XCTAssertFalse(controller.view.subviews.contains { $0 is UIScrollView })
    }

    func testCancelledDragCommitsNothingAndFlushesPendingNeighbour() {
        let controller = makeController()
        apply(controller)
        controller.beginInteraction()
        controller.updateInteraction(translation: -150)
        apply(controller, next: "ready-next")
        XCTAssertEqual(controller.installedPageKeys[3], "placeholder")
        controller.endInteraction(velocity: -800, cancelled: true, animated: false)
        XCTAssertTrue(commits.isEmpty)
        XCTAssertEqual(controller.installedPageKeys[3], "ready-next")
        XCTAssertEqual(interactions.last, false)
    }

    func testTwentyConsecutiveTurnsHaveOneCommitEach() async {
        let controller = makeController()
        apply(controller)
        for index in 1...20 {
            controller.beginInteraction()
            controller.updateInteraction(translation: -180)
            controller.endInteraction(velocity: -500, animated: false)
            apply(controller, page: "p\(index)", next: "p\(index + 1)")
            await drainMainQueue()
            XCTAssertEqual(commits.count, index)
            XCTAssertEqual(controller.visiblePageIdentity, "p\(index)")
            XCTAssertEqual(interactions.last, false)
        }
        XCTAssertEqual(commits, Array(repeating: 1, count: 20))
    }

    func testSecondFlickIsQueuedWhileCommittedModelIsBeingDelivered() async {
        let controller = makeController()
        apply(controller)
        controller.beginInteraction()
        controller.updateInteraction(translation: -180)
        controller.endInteraction(velocity: -500, animated: false)
        controller.beginInteraction()
        controller.updateInteraction(translation: -180)
        controller.endInteraction(velocity: -500, animated: false)
        XCTAssertEqual(commits, [1])
        apply(controller, page: "p1", next: "p2")
        XCTAssertEqual(commits, [1, 1])
        apply(controller, page: "p2", next: "p3")
        await drainMainQueue()
        XCTAssertEqual(controller.visiblePageIdentity, "p2")
        XCTAssertEqual(interactions.last, false)
    }

    func testActualTextViewFitsTheOnboardingLastChapterWithoutSafetyBuffer() {
        let book = OnboardingClassicBook.makeWelcomeBook()
        guard let chapter = book.chapters.last else { return XCTFail("missing fixture") }
        let typography = ReaderPageTypography(
            font: .systemFont(ofSize: 20), titleFont: .boldSystemFont(ofSize: 26),
            lineSpacing: 8, letterSpacing: 0, paragraphSpacing: 16, firstLineIndent: 40,
            titleSpacing: 12, contentWidth: 348, contentHeight: 702
        )
        let context = ReaderChapterPaginationContext(typography: typography, titleTypography: typography,
            chromeLayout: .header, imageStyle: .standard, viewportHeight: 844, pagePadding: 21,
            footerHeight: 14, traditionalChinese: false)
        let pages = ReaderChapterPaginator.paginate(chapterIndex: chapter.index, title: chapter.title,
                                                    paragraphs: chapter.paragraphs, context: context)
        XCTAssertFalse(pages.isEmpty)
        XCTAssertTrue(pages.flatMap(\.paragraphs).map(\.text).joined().contains("永驻字里行间"))
        for page in pages {
            let view = ReaderPrepaginatedTextView(usingTextLayoutManager: false)
            view.frame = CGRect(x: 0, y: 0, width: typography.contentWidth, height: typography.contentHeight)
            view.isScrollEnabled = false
            view.contentInsetAdjustmentBehavior = .never
            view.textContainerInset = .zero
            view.textContainer.lineFragmentPadding = 0
            view.setPage(ReaderPageTextBuilder.make(title: nil,
                paragraphs: page.paragraphs.map { .init(text: $0.text, isContinuation: $0.isContinuation, isHighlighted: false) },
                style: ReaderPageTextBuilder.layoutStyle(typography)))
            view.layoutIfNeeded()
            XCTAssertLessThanOrEqual(view.layoutManager.usedRect(for: view.textContainer).maxY,
                                     view.bounds.height + 0.5, "actual UITextView page \(page.pageOrdinal) clips")
        }
    }
}
