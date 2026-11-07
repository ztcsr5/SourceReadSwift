import SwiftUI
import WebKit
import XCTest
@testable import SourceReadSwift

final class Release117DetailTests: XCTestCase {
    @MainActor func testShortDetailSynopsisDoesNotDiscardCompleteSearchSynopsis() {
        let complete = "第一段简介。\n" + String(repeating: "这一段介绍人物与故事的完整背景。", count: 18) + "【简介结束】"
        XCTAssertEqual(BookDetailSummary.preferredIntro(detail: "第一段简介。…", fallback: complete), complete)
        XCTAssertEqual(BookDetailSummary.preferredIntro(detail: complete, fallback: "搜索摘要"), complete)
        XCTAssertEqual(BookDetailSummary.preferredIntro(detail: " <p> </p> ", fallback: complete), complete)
        XCTAssertNil(BookDetailSummary.preferredIntro(detail: nil, fallback: "   "))
    }

    @MainActor func testSynopsisFormattingPreservesParagraphsAndFinalCharacters() {
        let synopsis = "<p>第一段 &amp; 引子</p><p>第二段<br />完整结尾&#12290;</p>"
        XCTAssertEqual(BookDetailSummary.sanitizeIntro(synopsis), "第一段 & 引子\n第二段\n完整结尾。")
    }

    @MainActor func testPoppingCachedDetailCancelsBothBackgroundRequests() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = BookSource(bookSourceName: "Cancellation fixture", bookSourceUrl: "https://detail-cancel.invalid")
        let sources = SourceStore(persistence: SourcePersistence(rootURL: root))
        try sources.importSources([source])
        let book = SearchBook(name: "Cached book", author: nil, coverUrl: nil,
            bookUrl: source.bookSourceUrl + "/book", sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)
        let cache = BookTOCacheStore(rootURL: root)
        cache.save(detail: nil, chapters: [.init(title: "Chapter", url: book.bookUrl + "/1", bookUrl: book.bookUrl, index: 0)],
            sourceURL: book.sourceUrl, bookURL: book.bookUrl)
        let started = expectation(description: "Both cached refresh requests started")
        started.expectedFulfillmentCount = 2
        let cancelled = expectation(description: "Both requests cancelled when detail popped")
        cancelled.expectedFulfillmentCount = 2
        let engine = DetailCancellationEngine(started: started, cancelled: cancelled)
        let app = AppState(sourceStore: sources, bookTOCacheStore: cache, engine: engine)
        let route = DetailLifecycleRoute()
        let mounted = expectation(description: "Navigation root appeared")
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        window.rootViewController = UIHostingController(rootView:
            DetailLifecycleFixture(route: route, book: book, mounted: mounted).environmentObject(app))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        await fulfillment(of: [mounted], timeout: 3)
        route.isShown = true
        await fulfillment(of: [started], timeout: 3)
        route.isShown = false
        await fulfillment(of: [cancelled], timeout: 2)
    }

    @MainActor func testLocalDetailsRenderWithoutRecursivelyMountingReader() async throws {
        let local = LocalTextBook(title: "指点考古队，竟被当成盗墓贼 · 长标题排版检查", author: "小猴子 yyds",
            chapters: (0..<1009).map { LocalTextChapter(title: "第\($0 + 1)章 章节标题", paragraphs: ["正文"], index: $0) },
            language: "zh-CN")
        let book = BookshelfBook(localTextBook: local)
        for width: CGFloat in [320, 390] {
            try await snapshot(name: "local-details", width: width, content: NavigationStack {
                LocalBookMetadataView(book: book, onSelectChapter: { _ in })
            })
        }
    }

    @MainActor func testCompactRemoteDetailsRenderLongSynopsisAndMetadata() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SourceStore(persistence: SourcePersistence(rootURL: root))
        let source = BookSource(bookSourceName: "示例书源", bookSourceUrl: "https://release117-detail.invalid")
        try store.importSources([source])
        let app = AppState(sourceStore: store, engine: DetailFixtureEngine())
        let book = SearchBook(name: "剑来 · 长标题详情排版检查", author: "烽火戏诸侯", coverUrl: nil,
                              bookUrl: source.bookSourceUrl + "/book/" + UUID().uuidString,
                              sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl, intro: nil)
        for width: CGFloat in [320, 390] {
            try await snapshot(name: "remote-details", width: width, content: NavigationStack {
                BookDetailView(book: book)
            }.environmentObject(app))
        }
    }

    @MainActor private func snapshot<Content: View>(name: String, width: CGFloat, content: Content) async throws {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            let container = UIViewController()
            let host = UIHostingController(rootView: content)
            window.rootViewController = container
            window.makeKeyAndVisible()
            container.addChild(host); container.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            host.didMove(toParent: container)
            try await Task.sleep(nanoseconds: 400_000_000)
            host.view.layoutIfNeeded()
            func webCount(_ view: UIView) -> Int {
                (view is WKWebView ? 1 : 0) + view.subviews.reduce(0) { $0 + webCount($1) }
            }
            XCTAssertEqual(webCount(host.view), 0, "Detail must not create a nested reader")
            XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "release117-\(name)-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
    }
}

private final class DetailLifecycleRoute: ObservableObject {
    @Published var isShown = false
}

private struct DetailLifecycleFixture: View {
    @ObservedObject var route: DetailLifecycleRoute
    let book: SearchBook
    let mounted: XCTestExpectation
    @State private var hasReportedInitialAppearance = false

    var body: some View {
        NavigationStack {
            Text("Home").onAppear {
                guard !hasReportedInitialAppearance else { return }
                hasReportedInitialAppearance = true
                mounted.fulfill()
            }
                .navigationDestination(isPresented: $route.isShown) { BookDetailView(book: book) }
        }
    }
}

private actor DetailCancellationEngine: SourceEngine {
    let started: XCTestExpectation
    let cancelled: XCTestExpectation

    init(started: XCTestExpectation, cancelled: XCTestExpectation) {
        self.started = started
        self.cancelled = cancelled
    }

    private func waitUntilCancelled() async {
        started.fulfill()
        do { try await Task.sleep(nanoseconds: 30_000_000_000) }
        catch { if error is CancellationError { cancelled.fulfill() } }
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        await waitUntilCancelled()
        return .failure(.network("Cancelled fixture"))
    }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        await waitUntilCancelled()
        return .failure(.network("Cancelled fixture"))
    }
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> { .failure(.unsupported("Unused fixture")) }
    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .success(.init(status: .notConfigured, message: "Fixture", cookiePresent: false))
    }
}

private struct DetailFixtureEngine: SourceEngine {
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .success([]) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        .success(.init(name: book.name, author: book.author, coverUrl: nil, bookUrl: book.bookUrl,
                       sourceName: book.sourceName, sourceUrl: book.sourceUrl,
                       intro: String(repeating: "大千世界，无奇不有。阅读详情不应重复标题和作者；完整简介可以展开。", count: 10),
                       latestChapter: "第1009章 远行", wordCount: "2607万字", status: "连载中",
                       updateTime: "2026-11-02 12:30:00", kind: "仙侠 · 长分类名称排版验证"))
    }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        .success((0..<1009).map { .init(title: "第\($0 + 1)章 惊蛰", url: book.bookUrl + "/\($0)", bookUrl: book.bookUrl, index: $0) })
    }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> { .failure(.unsupported("Fixture does not open a reader")) }
    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .success(.init(status: .notConfigured, message: "Fixture", cookiePresent: false))
    }
}
