import SwiftUI
import WebKit
import XCTest
@testable import SourceReadSwift

final class ReaderScrollCadenceTests: XCTestCase {
    @MainActor func testCharacterJumpReportsItsPositionAfterAcknowledgementWithAnimationFramesHeld() async throws {
        let messages = ReaderPositionMessageProbe()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(messages, name: "reader")
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 760), configuration: configuration)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible(); host.view.addSubview(web)
        defer {
            web.stopLoading(); configuration.userContentController.removeScriptMessageHandler(forName: "reader")
            window.isHidden = true; previous?.makeKey()
        }
        let shell = WebReaderHTML.shell.replacingOccurrences(of: "<head>",
            with: "<head><script>window.requestAnimationFrame=function(){return 0;};</script>")
        web.loadHTMLString(shell, baseURL: nil)
        var ready = false
        for _ in 0..<100 {
            ready = (try? await web.evaluateJavaScript("!!window.__reader")) as? Bool == true
            if ready { break }; try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(ready)
        let style = WebReaderStylePayload.make(fontFamily: .system, fontSize: 20, lineSpacing: 8,
            pagePadding: 20, letterSpacing: 0, paragraphSpacing: 12, paragraphIndent: 40,
            titleSpacing: 16, footerHeight: 12, topInset: 50, textColor: .black, surfaceColor: .white,
            highlightColor: .yellow, accentColor: .blue, selectable: false)
        let encodedStyle = try JSONSerialization.data(withJSONObject: style.jsonObject)
        let styleJSON = String(decoding: encodedStyle, as: UTF8.self)
        _ = try await web.evaluateJavaScript("window.__reader.setStyle(JSON.parse(\(WebReaderJavaScriptLiteral.string(styleJSON))));")
        let text = String(repeating: "长段正文，模式切换不能回到段首。👩🏽‍💻", count: 150)
        let content = try XCTUnwrap(WebReaderContentPayloadBuilder.json(
            sections: [.init(chapterIndex: 0, title: "长段落", paragraphs: [text, "末段"])],
            showChapterEndBadge: false, traditionalChineseEnabled: false, revision: "held-frames"))
        _ = try await web.evaluateJavaScript("window.__reader.setContent(JSON.parse(\(WebReaderJavaScriptLiteral.string(content))));")
        _ = try await web.evaluateJavaScript("window.__reader.scrollToFlat(0,false,'character600','held-frames',600);")
        for _ in 0..<30 {
            if messages.bodies.contains(where: { $0["type"] as? String == "visible" }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let acknowledgement = try XCTUnwrap(messages.bodies.firstIndex(where: { $0["type"] as? String == "scroll-applied" }))
        let visible = try XCTUnwrap(messages.bodies.firstIndex(where: { $0["type"] as? String == "visible" }),
            "A covered reader must commit its restored position without a compositor frame")
        XCTAssertGreaterThan(visible, acknowledgement, "The native pending key is cleared by acknowledgement first")
        XCTAssertEqual(messages.bodies[visible]["revision"] as? String, "held-frames")
        let offset = try XCTUnwrap(messages.bodies[visible]["utf16Offset"] as? Int)
        XCTAssertGreaterThan(offset, 500)
        XCTAssertLessThanOrEqual(offset, 600)

        messages.bodies.removeAll()
        _ = try await web.evaluateJavaScript("window.__reader.resetScroll();")
        for _ in 0..<30 {
            if messages.bodies.contains(where: { $0["type"] as? String == "visible" }) { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let initial = try XCTUnwrap(messages.bodies.first { $0["type"] as? String == "visible" },
            "Opening at paragraph zero must report without a compositor frame")
        XCTAssertEqual(initial["flat"] as? Int, 0)
        XCTAssertEqual(initial["utf16Offset"] as? Int, 0)
        XCTAssertEqual(initial["revision"] as? String, "held-frames")
        let initialY = try await web.evaluateJavaScript("window.scrollY") as? Int
        XCTAssertEqual(initialY, 0)
    }

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
        let isSpyInstalled = try await web.evaluateJavaScript("window.readerScrollCommands=0;window.readerOriginalScroll=window.scrollTo.bind(window);window.scrollTo=function(){window.readerScrollCommands++;return window.readerOriginalScroll.apply(window,arguments);};typeof window.scrollTo === 'function';") as? Bool
        XCTAssertEqual(isSpyInstalled, true, "Return a bridge-supported value after installing the scroll spy")
        try await setContent([0, 1])
        let appendCommands = try await web.evaluateJavaScript("window.readerScrollCommands") as? Int
        XCTAssertEqual(appendCommands, 0, "Appending below the viewport must not cancel native deceleration")
        try await setContent([-1, 0, 1])
        let prependCommands = try await web.evaluateJavaScript("window.readerScrollCommands") as? Int
        XCTAssertGreaterThan(prependCommands ?? 0, 0, "A real prefix change must still restore its anchor")
    }

    @MainActor func testResolvingANextChapterPlaceholderDoesNotUnmountTheVisibleChapterOrStopInertia() async throws {
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
        let first = WebReaderSection(chapterIndex: 0, title: "当前章",
            paragraphs: Array(repeating: String(repeating: "正在惯性滚动的正文不能重挂。", count: 12), count: 80))
        let pending = WebReaderSection(chapterIndex: 1, title: "下一章", paragraphs: [], isReady: false)
        let base = WebReaderContentPayloadBuilder.Snapshot(sections: [first, pending], showChapterEndBadge: false,
                                                           traditionalChineseEnabled: false, revision: "pending")
        let resolved = [first, WebReaderSection(chapterIndex: 1, title: "下一章", paragraphs: ["预取就绪"])]
        let next = WebReaderContentPayloadBuilder.Snapshot(sections: resolved, showChapterEndBadge: false,
                                                           traditionalChineseEnabled: false, revision: "ready")
        let full = try XCTUnwrap(WebReaderContentPayloadBuilder.json(sections: [first, pending], snapshot: base))
        let delta = try XCTUnwrap(WebReaderContentPayloadBuilder.json(sections: resolved, snapshot: next, reusing: base))
        let result = try await web.evaluateJavaScript("""
        (() => {
          const reader = window.__reader;
          const started = reader.setContent(JSON.parse(\(WebReaderJavaScriptLiteral.string(full))));
          window.scrollTo(0,600);
          const content = document.getElementById('content');
          const current = content.firstElementChild;
          const previousY = window.scrollY;
          const observer = new MutationObserver(()=>{});
          observer.observe(content,{childList:true});
          let scrollCommands = 0;
          const originalScroll = window.scrollTo.bind(window);
          window.scrollTo = (...args)=>{scrollCommands++;originalScroll(...args);};
          const delta = JSON.parse(\(WebReaderJavaScriptLiteral.string(delta)));
          const stale = reader.setContent({...delta,baseRevision:'stale'});
          const accepted = reader.setContent(delta);
          const detached = observer.takeRecords().reduce((count,record)=>count+
            Array.from(record.removedNodes).filter(node=>node===current).length,0);
          observer.disconnect();
          return {started,stale,accepted,detached,scrollCommands,previousY,y:window.scrollY,
            sameNode:content.firstElementChild===current,nextText:content.lastElementChild.textContent};
        })();
        """) as? [String: Any]
        let outcome = try XCTUnwrap(result)
        XCTAssertEqual(outcome["started"] as? Bool, true)
        XCTAssertEqual(outcome["stale"] as? Bool, false)
        XCTAssertEqual(outcome["accepted"] as? Bool, true)
        XCTAssertEqual(outcome["detached"] as? Int, 0, "The current chapter must remain mounted when the next one becomes ready")
        XCTAssertEqual(outcome["scrollCommands"] as? Int, 0, "A below-viewport patch must not interrupt native deceleration")
        XCTAssertEqual(outcome["sameNode"] as? Bool, true)
        let before = try XCTUnwrap(outcome["previousY"] as? Double)
        let after = try XCTUnwrap(outcome["y"] as? Double)
        XCTAssertEqual(after, before, accuracy: 1)
        XCTAssertTrue((outcome["nextText"] as? String)?.contains("预取就绪") == true)
    }

    @MainActor func testNextChapterBodyArrivalPreservesItsVisibleTitleAndInertia() async throws {
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 760))
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible(); host.view.addSubview(web)
        defer { web.stopLoading(); window.isHidden = true; previous?.makeKey() }
        web.loadHTMLString(WebReaderHTML.shell, baseURL: nil)
        for _ in 0..<100 {
            if (try? await web.evaluateJavaScript("!!window.__reader")) as? Bool == true { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let first = WebReaderSection(chapterIndex: 0, title: "第一章",
            paragraphs: Array(repeating: String(repeating: "窗外的风穿过树梢。", count: 10), count: 40))
        let pending = WebReaderSection(chapterIndex: 1, title: "第二章", paragraphs: [], isReady: false)
        let base = WebReaderContentPayloadBuilder.Snapshot(sections: [first, pending], showChapterEndBadge: false,
            traditionalChineseEnabled: false, revision: "pending-title")
        let resolved = [first, WebReaderSection(chapterIndex: 1, title: "第二章",
            paragraphs: Array(repeating: String(repeating: "下一章的正文已经到达。", count: 8), count: 30))]
        let next = WebReaderContentPayloadBuilder.Snapshot(sections: resolved, showChapterEndBadge: false,
            traditionalChineseEnabled: false, revision: "resolved-title")
        let full = try XCTUnwrap(WebReaderContentPayloadBuilder.json(sections: [first, pending], snapshot: base))
        let delta = try XCTUnwrap(WebReaderContentPayloadBuilder.json(sections: resolved, snapshot: next, reusing: base))
        for footer in [24, 900] {
            let outcome = try await web.evaluateJavaScript("""
            (() => {
              window.__reader.setStyle({fontFamily:'sans-serif',fontWeight:400,fontSize:20,lineHeight:1.4,
                letterSpacing:0,paragraphSpacing:12,paragraphIndent:40,sidePadding:20,topInset:50,
                bottomInset:\(footer),titleSize:26,titleSpacing:16,textColor:'#000000',surfaceColor:'#ffffff',
                highlightColor:'#ffff00',accentColor:'#6666cc',selectable:false});
              window.__reader.setContent(JSON.parse(\(WebReaderJavaScriptLiteral.string(full))));
              const section = document.querySelector('[data-key="c1"]');
              const heading = section.firstElementChild;
              window.scrollTo(0,heading.getBoundingClientRect().top + window.scrollY - 50);
              const before = heading.getBoundingClientRect().top;
              const original = window.scrollTo.bind(window);
              let commands = 0;
              window.scrollTo = (...args)=>{commands++;original(...args);};
              const accepted = window.__reader.setContent(JSON.parse(\(WebReaderJavaScriptLiteral.string(delta))));
              window.scrollTo = original;
              return {accepted,commands,before,after:heading.getBoundingClientRect().top,
                sameHeading:document.querySelector('[data-key="c1"]').firstElementChild===heading,
                connected:heading.isConnected,paragraphs:section.querySelectorAll('.para').length};
            })();
            """) as? [String: Any]
            let result = try XCTUnwrap(outcome)
            XCTAssertEqual(result["accepted"] as? Bool, true)
            XCTAssertEqual(result["sameHeading"] as? Bool, true)
            XCTAssertEqual(result["connected"] as? Bool, true)
            XCTAssertEqual(result["commands"] as? Int, 0, "Resolving prose below the visible title must not cancel WebKit deceleration")
            XCTAssertEqual(result["paragraphs"] as? Int, 30)
            let before = try XCTUnwrap(result["before"] as? Double)
            let after = try XCTUnwrap(result["after"] as? Double)
            XCTAssertEqual(after, before, accuracy: 1)
            XCTAssertGreaterThan(before, 0)
            XCTAssertLessThan(before, 760)
        }
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

private final class ReaderPositionMessageProbe: NSObject, WKScriptMessageHandler {
    var bodies: [[String: Any]] = []
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { bodies.append(body) }
    }
}
