import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import SourceReadSwift

@MainActor
final class ReaderNativeNavigationTests: XCTestCase {
    func testStandaloneReaderAppliesItsOnAppearCursor() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
        let app = AppState()
        let session = ReaderNavigationSession(bookID: "standalone-state-fixture")
        session.didAppear()
        let content = ChapterContent(chapter: BookChapter(title: "状态边界", url: "local://state",
            bookUrl: "local://state", index: 0, isVip: false), title: "状态边界",
            paragraphs: (0..<60).map { "第\($0)段。初始定位必须通过实际 SwiftUI 更新传递到正文。" })
        let host = UIHostingController(rootView: ReaderView(bookID: "standalone-state-fixture",
            content: content, chapterIndex: 0, totalChapters: 1, initialParagraphIndex: 30)
            .environment(\.nativeReaderSession, session).environmentObject(app))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { session.commitExit(); window.isHidden = true; previous?.makeKey() }
        let ready = await eventually { session.hasPresentedContent }
        XCTAssertTrue(ready)
        let web = try XCTUnwrap(findWeb(host.view))
        let visible = try await web.evaluateJavaScript("""
            (() => {
                const rect = document.querySelector('p[data-flat="30"]')?.getBoundingClientRect();
                return !!rect && rect.bottom > 0 && rect.top < window.innerHeight;
            })()
            """)
        XCTAssertEqual(visible as? Bool, true,
                       "Reader state must update without a router or outer representable; \(session.renderingEvidence)")
    }

    func testNativeHostKeepsSwiftUIStateUpdatesAfterPush() async throws {
        let app = AppState()
        let outer = UIHostingController(rootView: ReaderNavigationHost().ignoresSafeArea().environmentObject(app))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = outer
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let mounted = await eventually { self.findNavigation(outer) != nil }
        XCTAssertTrue(mounted)
        let book = BookshelfBook(id: "host-state-fixture", title: "状态更新", author: "",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://state", intro: nil)
        var button: UIButton?
        let request = ReaderDestinationRequest(book: book) { _ in
            AnyView(HostedStateFixture(onMount: { button = $0 }))
        }
        XCTAssertTrue(app.readerNavigation.open(request))
        let appeared = await eventually { app.readerNavigation.reader?.session.phase == .reading && button != nil }
        XCTAssertTrue(appeared)
        let control = try XCTUnwrap(button)
        let initialized = await eventually { control.title(for: .normal) == "1" }
        XCTAssertTrue(initialized, "A minimal pushed SwiftUI view must render its onAppear state")
        control.sendActions(for: .touchUpInside)
        let changed = await eventually { control.title(for: .normal) == "2" }
        XCTAssertTrue(changed, "State must reach UIViewRepresentable after an event across the native hosting boundary")
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil }
        XCTAssertTrue(returned)
    }

    func testAppHostingBoundaryUsesTheWindowAndRevealsPositionedProse() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
        let app = AppState()
        let outer = UIHostingController(rootView: ReaderNavigationHost().ignoresSafeArea().environmentObject(app))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = outer
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let mounted = await eventually { self.findNavigation(outer) != nil }
        XCTAssertTrue(mounted)
        let navigation = try XCTUnwrap(findNavigation(outer))
        XCTAssertEqual(navigation.view.convert(navigation.view.bounds, to: window), window.bounds,
                       "The representable must not inset the UIKit navigation before UIKit applies its safe area")
        var book = BookshelfBook(id: "app-host-fixture", title: "真实容器", author: "",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://app-host", intro: nil)
        book.localContent = (0..<60).map { "正文第\($0)段。应用容器边界必须保留正文、定位与原生返回。" }
        book.currentChapterIndex = 0
        book.currentParagraphIndex = 30
        XCTAssertTrue(app.readerNavigation.open(.shelf(book)))
        let reader = try XCTUnwrap(app.readerNavigation.reader)
        let ready = await eventually { reader.session.hasPresentedContent }
        XCTAssertTrue(ready, "The full application hosting boundary must receive the actual WebKit render acknowledgement; stage=\(reader.session.openingStage) managed=\(reader.session.isOpeningManaged) appearances=\(reader.session.readerAppearances)")
        XCTAssertEqual(reader.session.webViewIdentities.count, 1)
        XCTAssertEqual(reader.session.shellLoads, 1)
        let web = try XCTUnwrap(findWeb(reader.view))
        let acceptsTouches = await eventually {
            let contentPoint = web.convert(CGPoint(x: web.bounds.midX, y: web.bounds.height * 0.42), to: window)
            return reader.session.phase == .reading
                && window.hitTest(contentPoint, with: nil)?.isDescendant(of: web) == true
        }
        XCTAssertTrue(acceptsTouches,
                      "The positioned prose must receive touches after UIKit arrival and the SwiftUI readiness update")
        let targetVisible = try await web.evaluateJavaScript("""
            (() => {
                const target = document.querySelector('p[data-flat="30"]');
                if (!target) return false;
                const rect = target.getBoundingClientRect();
                return rect.bottom > 0 && rect.top < window.innerHeight;
            })()
            """)
        let cursor = try await web.evaluateJavaScript("JSON.stringify({y:window.scrollY,visible:window.__reader.state.visible,position:document.querySelector('p[data-flat=\"30\"]')?.getBoundingClientRect().toJSON()})")
        XCTAssertEqual(targetVisible as? Bool, true,
                       "The saved paragraph must be in the actual viewport, not only mounted offscreen; \(reader.session.openingCursor); \(reader.session.renderingEvidence); \(cursor)")
        for _ in 0..<50 {
            let idle = try await web.evaluateJavaScript("performance.now() - window.__reader.state.lastScrollAt >= 260")
            if idle as? Bool == true { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = try await web.evaluateJavaScript("""
            (() => {
                const options = {clientX: window.innerWidth / 2, clientY: window.innerHeight * 0.42,
                                 pointerId: 1, pointerType: 'touch', isPrimary: true, bubbles: true};
                window.dispatchEvent(new PointerEvent('pointerdown', options));
                window.dispatchEvent(new PointerEvent('pointerup', options));
            })()
            """)
        let menuAppeared = await eventually { reader.session.lastMenuState }
        XCTAssertTrue(menuAppeared, "A valid content-zone tap must reach the menu state through the real JS bridge")
        let menuRendered = await eventually { reader.session.renderedMenuState && !reader.session.renderedTransitionState }
        XCTAssertTrue(menuRendered, "The SwiftUI subtree must update after the bridge tap; \(reader.session.renderingEvidence)")
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil }
        XCTAssertTrue(returned)
        XCTAssertEqual(navigation.viewControllers.count, 1)
    }

    func testRealReaderPushAndPopRetainTheRootAndDoNotOwnTabChrome() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
        let app = AppState()
        let root = UIHostingController(rootView: RootTabView().environmentObject(app))
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        app.readerNavigation.attach(navigation, appState: app)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let scene = previous?.windowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let mounted = await eventually { root.view.window != nil }
        XCTAssertTrue(mounted)
        let rootIdentity = ObjectIdentifier(root)
        var book = BookshelfBook(id: "native-navigation-fixture", title: "导航测试", author: "",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://navigation", intro: nil)
        book.localContent = (0..<50).map { "第\($0)段。阅读器必须保留真实 WebView 与阅读位置。" }
        book.currentChapterIndex = 0
        book.currentParagraphIndex = 30
        XCTAssertTrue(app.readerNavigation.open(.shelf(book)))
        let reader = try XCTUnwrap(app.readerNavigation.reader)
        let ready = await eventually { reader.session.webViewIdentities.count == 1
            && reader.session.hasPresentedContent && reader.session.phase == .reading }
        XCTAssertTrue(ready)
        let web = try XCTUnwrap(findWeb(reader.view))
        let positioned = try await web.evaluateJavaScript("""
            (() => {
                const rect = document.querySelector('p[data-flat="30"]')?.getBoundingClientRect();
                return !!rect && rect.bottom > 0 && rect.top < window.innerHeight;
            })()
            """)
        XCTAssertEqual(positioned as? Bool, true,
                       "A UIKit-rooted reader must apply the saved cursor; \(reader.session.renderingEvidence)")
        XCTAssertEqual(reader.session.shellLoads, 1)
        XCTAssertFalse(app.isTabChromeHidden, "The retained root bar must not participate in reader ownership")
        XCTAssertTrue(app.isReaderPresented)
        XCTAssertFalse(app.readerNavigation.open(.shelf(book)), "A duplicate tap cannot create a second reader")
        XCTAssertTrue(reader === app.readerNavigation.reader)
        // Cross the production recovery deadline: successful rendering must disarm it.
        try await Task.sleep(nanoseconds: 8_100_000_000)
        XCTAssertNotEqual(reader.session.openingStage, "position-timeout")
        XCTAssertTrue(reader.session.isContentReady)
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil && navigation.topViewController === root }
        XCTAssertTrue(returned)
        XCTAssertEqual(ObjectIdentifier(navigation.viewControllers[0]), rootIdentity)
        // A rendered document is parked instead of committed: the reader keeps
        // its live WebView for the next open of the same book.
        XCTAssertTrue(app.readerNavigation.hasDormantReader,
                      "A ready reader must be parked, not rebuilt, after returning")
        XCTAssertNotEqual(reader.session.phase, .closed)
        XCTAssertFalse(app.isReaderPresented)
        XCTAssertFalse(app.isTabChromeHidden)
    }

    func testOfflineProseStillOpensAfterItsBookSourceIsRemoved() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
        let app = AppState()
        let root = UIViewController()
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        app.readerNavigation.attach(navigation, appState: app)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        let sourceURL = "https://removed-source.invalid/\(UUID().uuidString)"
        let bookURL = "https://offline-reader.invalid/book"
        let chapter = BookChapter(title: "缓存章节", url: bookURL + "/12", bookUrl: bookURL, index: 12, isVip: false)
        let prose = "书源已经移除，仍然可以阅读完整的离线正文。"
        let cache = app.chapterContentCacheStore
        cache.save(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: [prose], nextContentUrl: nil),
                   sourceURL: sourceURL, purifyRules: [UUID().uuidString], retainOffline: true)
        defer { cache.invalidate(sourceURL: sourceURL, chapter: chapter) }
        let book = BookshelfBook(id: sourceURL, title: "离线测试", author: "", coverURL: nil,
            sourceName: "已移除书源", sourceURL: sourceURL, bookURL: bookURL, intro: nil, mediaKind: .text)
        XCTAssertNil(app.sourceStore.source(for: sourceURL))
        XCTAssertTrue(app.readerNavigation.open(.shelf(book, chapterIndex: chapter.index)))
        let reader = try XCTUnwrap(app.readerNavigation.reader)
        let ready = await eventually { reader.session.hasPresentedContent && reader.session.phase == .reading }
        XCTAssertTrue(ready, reader.session.renderingEvidence)
        let web = try XCTUnwrap(findWeb(reader.view))
        let visibleText = try await web.evaluateJavaScript("document.body.innerText") as? String
        XCTAssertTrue(visibleText?.contains(prose) == true)
        XCTAssertEqual(reader.session.shellLoads, 1)
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil && navigation.topViewController === root }
        XCTAssertTrue(returned)
    }

    /// The whole point of parking: a second open of the same book must not
    /// reload the shell or re-resolve the paragraph. This runs the real router,
    /// real hosting controller and real WKWebView.
    func testReopeningTheSameBookReusesTheParkedDocumentWithoutReloading() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
        let app = AppState()
        let root = UIViewController()
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        app.readerNavigation.attach(navigation, appState: app)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        var book = BookshelfBook(id: "parked-reader-fixture", title: "热续读", author: "",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://parked", intro: nil)
        book.localContent = (0..<40).map { "第\($0)段。复用的正文必须仍在原来的位置。" }
        book.currentChapterIndex = 0
        book.currentParagraphIndex = 20
        XCTAssertTrue(app.readerNavigation.open(.shelf(book)))
        let first = try XCTUnwrap(app.readerNavigation.reader)
        let firstReady = await eventually { first.session.phase == .reading && first.session.hasPresentedContent
            && first.session.shellLoads == 1 }
        XCTAssertTrue(firstReady, first.session.renderingEvidence)
        let firstSessionID = first.session.id
        let firstWeb = try XCTUnwrap(findWeb(first.view))
        app.readerNavigation.close()
        let parked = await eventually { app.readerNavigation.reader == nil && app.readerNavigation.hasDormantReader }
        XCTAssertTrue(parked)
        XCTAssertNotEqual(first.session.phase, .closed,
                          "A reusable reader must keep its document instead of committing the exit")

        XCTAssertTrue(app.readerNavigation.open(.shelf(book)))
        let second = try XCTUnwrap(app.readerNavigation.reader)
        XCTAssertTrue(second === first, "The same controller must be re-presented, not rebuilt")
        XCTAssertEqual(second.session.id, firstSessionID)
        XCTAssertEqual(second.session.shellLoads, 1, "Reopening must not reload the HTML shell")
        XCTAssertTrue(findWeb(second.view) === firstWeb, "The live WKWebView must survive the return")
        let resumed = await eventually { second.session.phase == .reading }
        XCTAssertTrue(resumed)
        let script = "(function(){var r=document.querySelector('p[data-flat=\"20\"]')"
            + "?document.querySelector('p[data-flat=\"20\"]').getBoundingClientRect():null;"
            + "return !!r && r.bottom>0 && r.top<window.innerHeight;})()"
        let positioned = try await firstWeb.evaluateJavaScript(script)
        XCTAssertEqual(positioned as? Bool, true,
                       "The parked document must still sit at the saved paragraph; \(second.session.renderingEvidence)")
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil }
        XCTAssertTrue(returned)
    }

    func testReaderOpenedFromASheetReturnsToThatSameSheet() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
        let app = AppState()
        let root = UIHostingController(rootView: RootTabView().environmentObject(app))
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        app.readerNavigation.attach(navigation, appState: app)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let sheet = UIHostingController(rootView: ReaderBookmarksView().environmentObject(app))
        sheet.modalPresentationStyle = .pageSheet
        navigation.present(sheet, animated: false)
        let mounted = await eventually { sheet.view.window != nil }
        XCTAssertTrue(mounted)
        var book = BookshelfBook(id: "sheet-native-fixture", title: "目录继续阅读", author: "",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://sheet", intro: nil)
        book.localContent = ["从已有的目录或者书签面板进入，退出后保留原面板。"]
        XCTAssertTrue(app.readerNavigation.open(.shelf(book)))
        let reader = try XCTUnwrap(app.readerNavigation.reader)
        let ready = await eventually { reader.session.phase == .reading && reader.session.shellLoads == 1
            && reader.session.hasPresentedContent }
        XCTAssertTrue(ready)
        XCTAssertTrue(reader.presentingViewController === sheet)
        XCTAssertEqual(navigation.viewControllers.count, 1)
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil && sheet.presentedViewController == nil }
        XCTAssertTrue(returned)
        XCTAssertTrue(navigation.presentedViewController === sheet)
        XCTAssertTrue(sheet.view.window === window)
        XCTAssertFalse(app.isReaderPresented)
        navigation.dismiss(animated: false)
    }

    /// 600 x 50 ms = 30 s. Was 15 s, which iOS 18 runners exceeded while
    /// launching WebContent (27.96 s observed on job 130871147672). The poll
    /// still returns as soon as the real condition holds.
    private func eventually(_ predicate: @escaping () -> Bool) async -> Bool {
        for _ in 0..<600 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }

    private func findNavigation(_ controller: UIViewController) -> ReaderNavigationController? {
        if let navigation = controller as? ReaderNavigationController { return navigation }
        for child in controller.children {
            if let navigation = findNavigation(child) { return navigation }
        }
        return nil
    }

    private func findWeb(_ view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = findWeb(child) { return web } }
        return nil
    }
}

private struct HostedStateFixture: View {
    let onMount: (UIButton) -> Void
    @State private var count = 0
    var body: some View {
        HostedStateButton(count: count, increment: { count += 1 }, onMount: onMount)
            .onAppear { count = 1 }
            .readerOpeningContentReady()
    }
}

private struct HostedStateButton: UIViewRepresentable {
    let count: Int
    let increment: () -> Void
    let onMount: (UIButton) -> Void
    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.addAction(UIAction { _ in increment() }, for: .touchUpInside)
        onMount(button)
        return button
    }
    func updateUIView(_ button: UIButton, context: Context) {
        button.setTitle(String(count), for: .normal)
    }
}
