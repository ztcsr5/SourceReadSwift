import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderSnapshotPresentationTests: XCTestCase {
    private var fixture: SnapshotReaderFixture?

    override func tearDown() async throws {
        if let fixture {
            if fixture.app.readerNavigation.snapshotPresentation?.phase == .returning {
                fixture.app.readerNavigation.snapshotPresentation?.endReturn(completes: true)
            } else {
                fixture.app.readerNavigation.close()
            }
            _ = await eventually(attempts: 100) { fixture.app.readerNavigation.reader == nil }
            fixture.restore()
        }
        fixture = nil
    }

    func testInteractiveSnapshotCancellationAndReopenPreserveHomeCoverAndRealProse() async throws {
        let fixture = try makeFixture(style: .coverInteractive)
        let mounted = await eventually { fixture.home.appearances == 1 && fixture.lifetime.appearances == 1 }
        XCTAssertTrue(mounted, "The actual home must mount before beginning the reader experiment")
        let originalCoverFrame = fixture.cover.convert(fixture.cover.bounds, to: fixture.window)
        var returns = 0
        var request = ReaderDestinationRequest.shelf(fixture.book, sourceID: fixture.sourceID)
        request.onReturn = { returns += 1 }
        XCTAssertTrue(fixture.app.readerNavigation.open(request))
        let reader = try XCTUnwrap(fixture.app.readerNavigation.reader)
        let presentation = try XCTUnwrap(fixture.app.readerNavigation.snapshotPresentation)
        XCTAssertEqual(presentation.phase, .opening)
        XCTAssertTrue(reader.view.isHidden, "The live full-screen reader must not cover the home behind the opening carrier")
        let ready = await eventually(attempts: webBootAttempts) {
            presentation.phase == .reading && reader.session.hasPresentedContent && reader.session.shellLoads == 1
        }
        guard ready else { return XCTFail("Real prose did not become ready: \(reader.session.renderingEvidence)") }
        XCTAssertFalse(reader.view.isHidden, "The live reader must become visible after the opening carrier settles")
        let web = try XCTUnwrap(findWeb(in: reader.view))
        XCTAssertNotNil(web.window)
        XCTAssertFalse(web.window === fixture.window, "The reader must have an independent surface in the same scene")
        XCTAssertTrue(web.window?.windowScene === fixture.window.windowScene)
        try await assertParagraphIsVisible(20, in: web)
        let shellLoads = reader.session.shellLoads
        let sessionID = reader.session.id
        assertHomeRetained(fixture, coverFrame: originalCoverFrame)
        XCTAssertFalse(fixture.app.isTabChromeHidden)
        XCTAssertTrue(fixture.app.isReaderPresented)
        XCTAssertFalse(fixture.app.readerNavigation.open(request), "Repeated taps must not create another reader window")

        presentation.beginReturn(interactive: true)
        presentation.updateReturn(progress: 0.35)
        XCTAssertEqual(presentation.phase, .returning)
        XCTAssertTrue(reader.view.isHidden, "The live reader must leave rendering while its static copy is animated")
        XCTAssertEqual(reader.view.transform, .identity, "Only the disposable snapshot may scale")
        assertHomeRetained(fixture, coverFrame: originalCoverFrame)
        XCTAssertTrue(fixture.app.isReaderPresented, "The shelf must stay frozen until the return really completes")
        XCTAssertEqual(returns, 0)
        presentation.endReturn(completes: false)
        let cancelled = await eventually(attempts: 100) { presentation.phase == .reading }
        XCTAssertTrue(cancelled)
        XCTAssertTrue(fixture.app.readerNavigation.reader === reader)
        XCTAssertTrue(findWeb(in: reader.view) === web)
        XCTAssertEqual(reader.session.id, sessionID)
        XCTAssertEqual(reader.session.shellLoads, shellLoads)
        XCTAssertFalse(reader.view.isHidden)
        XCTAssertTrue(reader.view.isUserInteractionEnabled)
        try await assertParagraphIsVisible(20, in: web)
        assertHomeRetained(fixture, coverFrame: originalCoverFrame)
        capture(window: try XCTUnwrap(reader.view.window), name: "snapshot-reader-return-cancelled")

        fixture.app.readerNavigation.close()
        let returned = await eventually(attempts: 100) { fixture.app.readerNavigation.reader == nil }
        XCTAssertTrue(returned)
        XCTAssertEqual(returns, 1)
        XCTAssertFalse(fixture.app.isReaderPresented)
        XCTAssertTrue(fixture.window.isKeyWindow)
        XCTAssertTrue(fixture.app.readerNavigation.hasDormantReader)
        assertHomeRetained(fixture, coverFrame: originalCoverFrame)

        XCTAssertTrue(fixture.app.readerNavigation.open(request))
        let reopened = try XCTUnwrap(fixture.app.readerNavigation.reader)
        let resumed = await eventually(attempts: 100) {
            fixture.app.readerNavigation.snapshotPresentation?.phase == .reading
        }
        XCTAssertTrue(resumed)
        XCTAssertTrue(reopened === reader)
        XCTAssertTrue(findWeb(in: reopened.view) === web)
        XCTAssertEqual(reopened.session.id, sessionID)
        XCTAssertEqual(reopened.session.shellLoads, shellLoads)
        try await assertParagraphIsVisible(20, in: web)
        fixture.app.readerNavigation.close()
        let closedAgain = await eventually(attempts: 100) { fixture.app.readerNavigation.reader == nil }
        XCTAssertTrue(closedAgain)
        XCTAssertEqual(returns, 2)
        assertHomeRetained(fixture, coverFrame: originalCoverFrame)
        capture(window: fixture.window, name: "snapshot-reader-home-retained-after-two-returns")
    }

    func testSnapshotReaderFromPresentedDetailReturnsToThatSameDetail() async throws {
        let fixture = try makeFixture(style: .coverFlight)
        let mounted = await eventually { fixture.home.appearances == 1 }
        XCTAssertTrue(mounted)
        let detail = SnapshotDetailController()
        detail.modalPresentationStyle = .pageSheet
        fixture.navigation.present(detail, animated: false)
        let detailReady = await eventually { detail.appearances == 1 && detail.view.window === fixture.window }
        XCTAssertTrue(detailReady)
        let homeAppearances = fixture.home.appearances
        let homeDisappearances = fixture.home.disappearances
        let detailSource = "snapshot-detail-" + UUID().uuidString
        ReaderZoomSources.shared.register(detail.anchor, id: detailSource)
        let coverFrame = detail.cover.convert(detail.cover.bounds, to: fixture.window)
        let request = ReaderDestinationRequest(book: fixture.book, sourceID: detailSource) { _ in
            AnyView(Text("书籍详情进入的阅读内容").readerOpeningContentReady())
        }
        XCTAssertTrue(fixture.app.readerNavigation.open(request))
        let reader = try XCTUnwrap(fixture.app.readerNavigation.reader)
        let opened = await eventually(attempts: 100) {
            fixture.app.readerNavigation.snapshotPresentation?.phase == .reading
        }
        XCTAssertTrue(opened)
        XCTAssertNil(reader.presentingViewController)
        XCTAssertTrue(fixture.navigation.presentedViewController === detail)
        XCTAssertTrue(detail.view.window === fixture.window)
        XCTAssertEqual(detail.appearances, 1)
        XCTAssertEqual(detail.disappearances, 0)
        XCTAssertEqual(fixture.navigation.viewControllers.count, 1)
        fixture.app.readerNavigation.close()
        let returned = await eventually(attempts: 100) { fixture.app.readerNavigation.reader == nil }
        XCTAssertTrue(returned)
        XCTAssertTrue(fixture.navigation.presentedViewController === detail)
        XCTAssertNil(detail.presentedViewController)
        XCTAssertTrue(detail.view.window === fixture.window)
        XCTAssertTrue(fixture.window.isKeyWindow)
        XCTAssertEqual(detail.appearances, 1)
        XCTAssertEqual(detail.disappearances, 0)
        XCTAssertEqual(fixture.home.appearances, homeAppearances)
        XCTAssertEqual(fixture.home.disappearances, homeDisappearances)
        XCTAssertFalse(detail.cover.isHidden)
        XCTAssertEqual(detail.cover.alpha, 1)
        XCTAssertEqual(detail.cover.convert(detail.cover.bounds, to: fixture.window), coverFrame)
        capture(window: fixture.window, name: "snapshot-reader-returned-to-original-detail")
        fixture.navigation.dismiss(animated: false)
    }

    func testClosingDuringOpeningReleasesOnlyTheReaderWindow() async throws {
        let fixture = try makeFixture(style: .coverFlight)
        let mounted = await eventually { fixture.home.appearances == 1 && fixture.lifetime.appearances == 1 }
        XCTAssertTrue(mounted)
        let coverFrame = fixture.cover.convert(fixture.cover.bounds, to: fixture.window)
        let request = ReaderDestinationRequest(book: fixture.book, sourceID: fixture.sourceID) { _ in
            AnyView(Text("取消开卷").readerOpeningContentReady())
        }
        XCTAssertTrue(fixture.app.readerNavigation.open(request))
        XCTAssertEqual(fixture.app.readerNavigation.snapshotPresentation?.phase, .opening)
        fixture.app.readerNavigation.close()
        let closed = await eventually(attempts: 100) { fixture.app.readerNavigation.reader == nil }
        XCTAssertTrue(closed)
        XCTAssertFalse(fixture.app.isReaderPresented)
        XCTAssertTrue(fixture.window.isKeyWindow)
        assertHomeRetained(fixture, coverFrame: coverFrame)
    }

    func testOneShotSweepRejectsShortVerticalAndReversedIntents() {
        XCTAssertFalse(ReaderSnapshotGesturePolicy.triggers(translation: CGPoint(x: 7, y: 0), velocity: CGPoint(x: 2_000, y: 0)))
        XCTAssertFalse(ReaderSnapshotGesturePolicy.triggers(translation: CGPoint(x: 27, y: 0), velocity: CGPoint(x: 100, y: 0)))
        XCTAssertFalse(ReaderSnapshotGesturePolicy.triggers(translation: CGPoint(x: 60, y: 80), velocity: CGPoint(x: 900, y: 1_000)))
        XCTAssertFalse(ReaderSnapshotGesturePolicy.triggers(translation: CGPoint(x: -70, y: 0), velocity: CGPoint(x: -900, y: 0)))
        XCTAssertTrue(ReaderSnapshotGesturePolicy.triggers(translation: CGPoint(x: 28, y: 0), velocity: .zero))
        XCTAssertTrue(ReaderSnapshotGesturePolicy.triggers(translation: CGPoint(x: 10, y: 0), velocity: CGPoint(x: 800, y: 0)))
    }

    private func makeFixture(style: ReaderNavigationStyle) throws -> SnapshotReaderFixture {
        let fixture = try SnapshotReaderFixture(style: style)
        self.fixture = fixture
        return fixture
    }

    private var webBootAttempts: Int {
        if #available(iOS 18.0, *) { return 600 }
        return 1_800
    }

    private func eventually(attempts: Int = 100, _ condition: () -> Bool) async -> Bool {
        for _ in 0..<attempts {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private func assertHomeRetained(_ fixture: SnapshotReaderFixture, coverFrame: CGRect,
                                    file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(fixture.navigation.topViewController === fixture.home, file: file, line: line)
        XCTAssertEqual(fixture.navigation.viewControllers.count, 1, file: file, line: line)
        XCTAssertTrue(fixture.home.view.window === fixture.window, file: file, line: line)
        XCTAssertEqual(fixture.home.appearances, 1, file: file, line: line)
        XCTAssertEqual(fixture.home.disappearances, 0, file: file, line: line)
        XCTAssertEqual(fixture.lifetime.appearances, 1, file: file, line: line)
        XCTAssertEqual(fixture.lifetime.disappearances, 0, file: file, line: line)
        XCTAssertFalse(fixture.cover.isHidden, file: file, line: line)
        XCTAssertEqual(fixture.cover.alpha, 1, file: file, line: line)
        XCTAssertEqual(fixture.cover.transform, .identity, file: file, line: line)
        XCTAssertEqual(fixture.cover.convert(fixture.cover.bounds, to: fixture.window), coverFrame, file: file, line: line)
    }

    private func assertParagraphIsVisible(_ index: Int, in web: WKWebView) async throws {
        let visible = try await web.evaluateJavaScript("""
            (() => {
                const rect = document.querySelector('p[data-flat="\(index)"]')?.getBoundingClientRect();
                return !!rect && rect.bottom > 0 && rect.top < window.innerHeight;
            })()
            """)
        XCTAssertEqual(visible as? Bool, true, "The original paragraph must still be in the visible viewport")
    }

    private func findWeb(in view: UIView) -> WKWebView? {
        if let web = view as? WKWebView { return web }
        for child in view.subviews { if let web = findWeb(in: child) { return web } }
        return nil
    }

    private func capture(window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private final class SnapshotReaderFixture {
    let app: AppState
    let home: SnapshotHomeController
    let navigation: ReaderNavigationController
    let window: UIWindow
    let book: BookshelfBook
    let lifetime: SnapshotHomeLifetime
    let cover = UIView(frame: CGRect(x: 36, y: 170, width: 100, height: 148))
    let sourceID = "snapshot-source-" + UUID().uuidString
    private let previousKeyWindow: UIWindow?
    private let savedPreferences: [(String, Any?)]

    init(style: ReaderNavigationStyle) throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let preferences = UserDefaults.standard
        savedPreferences = [ReaderNavigationStyle.defaultsKey, "reader.mode", "reader.textSelectionEnabled",
            BookshelfStore.welcomeSeedPreferenceKey].map { ($0, preferences.object(forKey: $0)) }
        preferences.set(style.rawValue, forKey: ReaderNavigationStyle.defaultsKey)
        preferences.set("scroll", forKey: "reader.mode")
        preferences.set(false, forKey: "reader.textSelectionEnabled")
        preferences.set(true, forKey: BookshelfStore.welcomeSeedPreferenceKey)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-navigation-" + UUID().uuidString)
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: directory),
            groupPersistence: BookshelfGroupPersistence(rootURL: directory))
        shelf.addLocalTextBook(LocalTextBook(title: "留在原位的书", author: "转场测试", chapters: [
            LocalTextChapter(title: "原段落", paragraphs: (0..<70).map {
                "第\($0)段。" + String(repeating: "快照退场之后，原来的文字、位置和主页都应留在原处。", count: 4)
            }, index: 0)
        ]))
        let added = try XCTUnwrap(shelf.books.first)
        shelf.updateReadingProgress(bookID: added.id, chapterIndex: 0, chapterTitle: "原段落", totalChapters: 1, paragraphIndex: 20)
        book = try XCTUnwrap(shelf.book(id: added.id))
        let resolvedApp = AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: directory)), bookshelfStore: shelf,
            chapterContentCacheStore: ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: directory)),
            bookTOCacheStore: BookTOCacheStore(rootURL: directory),
            readingHistoryStore: ReadingHistoryStore(persistence: ReadingHistoryPersistence(rootURL: directory)))
        let resolvedLifetime = SnapshotHomeLifetime()
        let resolvedHome = SnapshotHomeController(rootView: AnyView(RootTabView(appState: resolvedApp).environmentObject(resolvedApp)
            .onAppear { resolvedLifetime.appearances += 1 }
            .onDisappear { resolvedLifetime.disappearances += 1 }))
        let resolvedNavigation = ReaderNavigationController(rootViewController: resolvedHome)
        app = resolvedApp
        lifetime = resolvedLifetime
        home = resolvedHome
        navigation = resolvedNavigation
        window = UIWindow(windowScene: scene)
        navigation.setNavigationBarHidden(true, animated: false)
        app.readerNavigation.attach(navigation, appState: app)
        window.frame = scene.screen.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        cover.backgroundColor = .systemIndigo
        cover.layer.cornerRadius = 10
        home.view.addSubview(cover)
        let anchor = UIView(frame: cover.bounds)
        anchor.isUserInteractionEnabled = false
        cover.addSubview(anchor)
        ReaderZoomSources.shared.register(anchor, id: sourceID)
    }

    func restore() {
        window.isHidden = true
        window.rootViewController = nil
        previousKeyWindow?.makeKey()
        for (key, value) in savedPreferences { UserDefaults.standard.set(value, forKey: key) }
    }
}

@MainActor
private final class SnapshotHomeLifetime {
    var appearances = 0
    var disappearances = 0
}

private final class SnapshotHomeController: UIHostingController<AnyView> {
    private(set) var appearances = 0
    private(set) var disappearances = 0
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appearances += 1 }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); disappearances += 1 }
}

private final class SnapshotDetailController: UIViewController {
    private(set) var appearances = 0
    private(set) var disappearances = 0
    let cover = UIView(frame: CGRect(x: 40, y: 80, width: 120, height: 180))
    let anchor = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 180))
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        cover.backgroundColor = .systemTeal
        view.addSubview(cover)
        cover.addSubview(anchor)
    }
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appearances += 1 }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); disappearances += 1 }
}
