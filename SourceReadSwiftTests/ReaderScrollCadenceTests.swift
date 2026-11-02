import SwiftUI
import WebKit
import XCTest
@testable import SourceReadSwift

final class ReaderScrollCadenceTests: XCTestCase {
    @MainActor func testAppendingAPrefetchDoesNotIssueAScrollCommandButPrependingStillAnchors() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 760))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible(); host.view.addSubview(web)
        defer { web.stopLoading(); window.isHidden = true; previous?.makeKey() }
        web.loadHTMLString(WebReaderHTML.shell, baseURL: nil)
        var ready = false
        for _ in 0..<100 {
            ready = (try? await web.evaluateJavaScript("!!window.__reader")) as? Bool == true
            if ready { break }; try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(ready)
        func setContent(_ chapters: [Int]) async throws {
            let sections = chapters.map { WebReaderSection(chapterIndex: $0, title: "章\($0)", paragraphs: Array(repeating: "连续滚动正文，原生惯性不应被预取打断。", count: 30)) }
            let json = try XCTUnwrap(WebReaderContentPayloadBuilder.json(sections: sections, showChapterEndBadge: false,
                traditionalChineseEnabled: false, revision: chapters.description))
            _ = try await web.evaluateJavaScript("window.__reader.setContent(JSON.parse(\(WebReaderJavaScriptLiteral.string(json))));")
        }
        try await setContent([0])
        _ = try await web.evaluateJavaScript("window.readerScrollCommands=0;window.readerOriginalScroll=window.scrollTo.bind(window);window.scrollTo=function(){window.readerScrollCommands++;return window.readerOriginalScroll.apply(window,arguments);};")
        try await setContent([0, 1])
        let appendCommands = try await web.evaluateJavaScript("window.readerScrollCommands") as? Int
        XCTAssertEqual(appendCommands, 0, "Appending below the viewport must not cancel native deceleration")
        try await setContent([-1, 0, 1])
        let prependCommands = try await web.evaluateJavaScript("window.readerScrollCommands") as? Int
        XCTAssertGreaterThan(prependCommands ?? 0, 0, "A real prefix change must still restore its anchor")
    }

    @MainActor func testPositionOnlyUpdatesDoNotRebuildTypographyOrFontLookup() async throws {
        func fixture(index: Int = -1, size: Double = 20) -> WebScrollReaderView {
            WebScrollReaderView(sections: [.init(chapterIndex: 0, title: "第一章", paragraphs: ["正文"])],
            contentFingerprint: "cadence", fontSize: size, lineSpacing: 8, pagePadding: 20, letterSpacing: 0,
            paragraphSpacing: 12, paragraphIndent: 40, titleSpacing: 12, footerHeight: 40,
            textColor: .black, highlightColor: .yellow, currentParagraphIndex: index, scrollTarget: nil,
            scrollRequestKey: nil, animatedScrollDuration: 0, textSelectionEnabled: false, onVisibleParagraph: { _ in })
        }
        let initial = fixture()
        let coordinator = initial.makeCoordinator(), web = coordinator.makeWebView(initialView: initial)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible()
        host.view.addSubview(web); web.frame = CGRect(x: 0, y: 0, width: 390, height: 760)
        defer { coordinator.tearDown(webView: web); window.isHidden = true; previous?.makeKey() }
        for _ in 0..<100 {
            if coordinator.styleBuildCount > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertEqual(web.scrollView.decelerationRate, .normal)
        XCTAssertGreaterThan(coordinator.styleBuildCount, 0)
        let before = coordinator.styleBuildCount
        for index in 0..<50 { coordinator.update(view: fixture(index: index), webView: web) }
        XCTAssertEqual(coordinator.styleBuildCount, before, "Scroll updates must not repeat font resolution even when the final payload is equal")
        coordinator.update(view: fixture(size: 21), webView: web)
        XCTAssertEqual(coordinator.styleBuildCount, before + 1, "Real typography changes must still reach the document")
    }
}
