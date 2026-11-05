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

    @MainActor func testCompletedShellWithMissingBridgeRecoversWithoutChangingItsCharacterCursor() async throws {
        try await assertStartupRecovery(emptiesDocument: false)
    }

    @MainActor func testCompletedEmptyDocumentRecoversWithoutChangingItsCharacterCursor() async throws {
        try await assertStartupRecovery(emptiesDocument: true)
    }

    @MainActor func testTerminatedStartupProcessReplaysTheCursorWithOneBoundedRecovery() async throws {
        try await assertStartupRecovery(emptiesDocument: false, simulatesTermination: true)
    }

    @MainActor private func assertStartupRecovery(emptiesDocument: Bool, simulatesTermination: Bool = false) async throws {
        var offset = -1, applied = false
        let text = String(repeating: "长段正文，恢复不能回到段首。👩🏽‍💻", count: 150)
        let fixture = WebScrollReaderView(
            sections: [WebReaderSection(chapterIndex: 0, title: "启动恢复", paragraphs: [text, "末段"])],
            contentFingerprint: "missing-bridge-regression", fontSize: 20, lineSpacing: 8,
            pagePadding: 20, letterSpacing: 0, paragraphSpacing: 12, paragraphIndent: 40,
            titleSpacing: 16, footerHeight: 12, topInset: 50, textColor: .black,
            highlightColor: .yellow, currentParagraphIndex: -1, scrollTarget: 0,
            scrollRequestKey: "restore-character-600", scrollTargetUTF16Offset: 600,
            animatedScrollDuration: 0, textSelectionEnabled: false,
            onVisibleParagraph: { _ in }, onVisiblePosition: { _, value in offset = value },
            onScrollTargetApplied: { applied = true })
        let coordinator = fixture.makeCoordinator()
        let fault = ReaderStartupBridgeFault(coordinator: coordinator)
        let web = coordinator.makeWebView(initialView: fixture, prepareBeforeNavigation: { web in
            guard !simulatesTermination else { return }
            web.configuration.userContentController.removeScriptMessageHandler(forName: "reader")
            web.configuration.userContentController.add(fault, name: "reader")
            web.configuration.userContentController.add(fault, name: "bridgeFault")
            web.configuration.userContentController.addUserScript(WKUserScript(
                source: """
                    Object.defineProperty(window, '__reader', {configurable:true, get:function(){return undefined;}, set:function(){}});
                    window.addEventListener('DOMContentLoaded', function(){
                      \(emptiesDocument ? "document.body.replaceChildren();" : "")
                      window.webkit.messageHandlers.bridgeFault.postMessage('injected');
                    });
                    """,
                injectionTime: .atDocumentStart, forMainFrameOnly: true))
        })
        if simulatesTermination {
            coordinator.webViewWebContentProcessDidTerminate(web)
            coordinator.webViewWebContentProcessDidTerminate(web)
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIViewController()
        window.rootViewController = host
        host.view.addSubview(web); web.frame = window.bounds
        window.makeKeyAndVisible()
        defer {
            coordinator.tearDown(webView: web)
            web.configuration.userContentController.removeScriptMessageHandler(forName: "bridgeFault")
            window.isHidden = true; previous?.makeKey()
        }
        for _ in 0..<150 {
            if applied && offset > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if simulatesTermination { XCTAssertEqual(fault.injections, 0) }
        else { XCTAssertEqual(fault.injections, 1) }
        XCTAssertEqual(coordinator.startupRecoveryCount, 1)
        XCTAssertTrue(applied, "A verified complete shell without its bridge must recover, not spin forever")
        XCTAssertGreaterThan(offset, 500)
        XCTAssertLessThanOrEqual(offset, 600, "Recovery must replay the unchanged character cursor, not reset to paragraph start")
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
        let previousKeyWindow = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: fixture)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previousKeyWindow?.makeKey() }
        for _ in 0..<150 {
            if applied && offset > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        if !applied || offset <= 500 {
            func findWeb(_ root: UIView) -> WKWebView? {
                if let web = root as? WKWebView { return web }
                return root.subviews.lazy.compactMap(findWeb).first
            }
            if let web = findWeb(host.view) {
                let diagnostic = try? await web.evaluateJavaScript("JSON.stringify({ready:document.readyState,bridge:!!window.__reader,paragraphs:document.querySelectorAll('.para').length,y:window.scrollY,height:document.documentElement.scrollHeight,visibility:document.visibilityState})")
                print("WEB_POSITION_DIAGNOSTIC \(diagnostic ?? "no JavaScript response") loading=\(web.isLoading) bounds=\(web.bounds)")
            }
        }
        XCTAssertTrue(applied, "The real WebKit document must acknowledge the character jump")
        XCTAssertGreaterThan(offset, 500, "Paragraph zero must not silently restore to its start")
        XCTAssertLessThanOrEqual(offset, 600, "The visible line should contain the requested character")
    }
}

private final class ReaderStartupBridgeFault: NSObject, WKScriptMessageHandler {
    private(set) var injections = 0
    private let coordinator: WebScrollReaderView.Coordinator
    private var canForwardReaderMessages = false

    init(coordinator: WebScrollReaderView.Coordinator) {
        self.coordinator = coordinator
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "reader" {
            if canForwardReaderMessages {
                coordinator.userContentController(userContentController, didReceive: message)
            }
            return
        }
        // Model a shell whose bootstrap never acknowledged readiness. Otherwise
        // the intact script's ready/fatal messages exercise a different recovery.
        injections += 1
        userContentController.removeAllUserScripts()
        canForwardReaderMessages = true
    }
}
