import XCTest
@testable import SourceReadSwift

@MainActor
final class ExploreBrowsingTests: XCTestCase {
    func testRetryKeepsMenuAndPageRequestsSeparateAndDoesNotLoseEarlierBooks() async throws {
        let fixture = try makeLibrary(failsOnce: true)
        let model = ExploreViewModel(defaults: fixture.defaults)
        model.bind(appState: fixture.state)
        try await settle(model)
        guard case .menu = model.failure else { return XCTFail("Expected a failed menu") }
        model.retry()
        try await settle(model)
        XCTAssertEqual(model.books.map(\.name), ["1"])
        model.loadNextPage()
        try await settle(model)
        guard case .page(2, _) = model.failure else { return XCTFail("Expected a failed second page") }
        XCTAssertEqual(model.books.map(\.name), ["1"])
        model.loadNextPage() // Showing the last row again must not loop on a failed request.
        model.retry()
        try await settle(model)
        XCTAssertEqual(model.books.map(\.name), ["1", "2"])
        model.loadNextPage()
        try await settle(model)
        XCTAssertFalse(model.canLoadMore)
        let menus = await fixture.engine.menus
        let pages = await fixture.engine.pages
        XCTAssertEqual(menus, ["A", "A"])
        XCTAssertEqual(pages, [1, 2, 2, 3])
        withExtendedLifetime(fixture.state) {}
    }

    func testBookmarksSurviveRelaunchWithoutMixingSourcesAndSkipDisabledOrMissingColumns() async throws {
        let fixture = try makeLibrary()
        let model = ExploreViewModel(defaults: fixture.defaults)
        model.bind(appState: fixture.state)
        try await settle(model)
        let first = try XCTUnwrap(model.selectedBookmark)
        model.toggleBookmark(first)
        let other = try XCTUnwrap(model.availableSources.last)
        model.selectSource(other)
        try await settle(model)
        let second = try XCTUnwrap(model.selectedBookmark)
        model.toggleBookmark(second)
        XCTAssertEqual(first.title, second.title)
        XCTAssertNotEqual(first, second)

        let reopened = ExploreViewModel(defaults: fixture.defaults)
        reopened.bind(appState: fixture.state)
        try await settle(reopened)
        XCTAssertEqual(reopened.visibleBookmarks, [second, first])
        reopened.open(second)
        try await settle(reopened)
        XCTAssertEqual(reopened.books.first?.sourceUrl, other.id)
        fixture.state.sourceStore.setEnabled(false, for: [other.id])
        reopened.reconcileSources()
        try await settle(reopened)
        XCTAssertEqual(reopened.visibleBookmarks, [first])
        XCTAssertEqual(reopened.books.first?.sourceUrl, first.sourceID)
        fixture.state.sourceStore.setEnabled(true, for: [other.id])
        reopened.reconcileSources()
        XCTAssertEqual(reopened.visibleBookmarks, [second, first])

        try fixture.state.sourceStore.importSources([BookSource(bookSourceName: other.bookSourceName,
            bookSourceUrl: other.id, exploreUrl: "换了栏目::/updated")])
        reopened.reconcileSources()
        let pagesBefore = await fixture.engine.pages
        reopened.open(second)
        try await settle(reopened)
        XCTAssertEqual(reopened.unavailableBookmark, second)
        XCTAssertNil(reopened.selectedCategory)
        let pagesAfter = await fixture.engine.pages
        XCTAssertEqual(pagesAfter, pagesBefore, "A missing shortcut must never issue the stale route or silently open another column")
    }

    func testUniqueTitlesFollowRotatingRoutesButAmbiguousTitlesNeverGuess() throws {
        let a = ExploreCategory(title: "来信", url: "/a", group: "短篇")
        let b = ExploreCategory(title: "来信", url: "/b", group: "短篇")
        let named = ExploreBookmark(sourceID: "A", category: a, in: [a])
        XCTAssertEqual(named.resolve(in: [b]), b)
        XCTAssertNil(named.resolve(in: [a, b]))
        let precise = ExploreBookmark(sourceID: "A", category: b, in: [a, b])
        let stored = try PropertyListEncoder().encode(precise)
        let restored = try PropertyListDecoder().decode(ExploreBookmark.self, from: stored)
        XCTAssertEqual(restored.resolve(in: [b, a]), b)
        XCTAssertNil(restored.resolve(in: [a]))
    }

    func testIndexSamplesGroupsAndIncludesTheActiveDeepColumn() async throws {
        let fixture = try makeLibrary()
        let model = ExploreViewModel(defaults: fixture.defaults)
        model.bind(appState: fixture.state)
        try await settle(model)
        XCTAssertEqual(model.inlineCategories.map(\.title), ["来信", "推理", "散文", "诗"])
        let last = try XCTUnwrap(model.categories.last)
        model.selectCategory(last)
        try await settle(model)
        XCTAssertEqual(model.inlineCategories.last, last)
        XCTAssertEqual(model.selectedCategory, last)
        let menus = await fixture.engine.menus
        XCTAssertEqual(menus, ["A"], "Opening the index must not fetch other sources")
        withExtendedLifetime(fixture.state) {}
    }

    private func settle(_ model: ExploreViewModel) async throws {
        for _ in 0..<500 {
            if !model.isLoadingMenu && !model.isLoading && !model.isLoadingMore { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Offline discovery did not settle within five seconds")
    }

    private func makeLibrary(failsOnce: Bool = false) throws -> (state: AppState, defaults: UserDefaults, engine: BrowseFixture) {
        let suite = "ExploreBrowsingTests." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: suite)
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        }
        let menu = "短篇&&来信::/first&&夜话::/night\n故事&&推理::/mystery\n随笔&&散文::/prose\n文集&&诗::/poetry&&游记::/travel"
        let sources = ["A", "B"].map { BookSource(bookSourceName: $0, bookSourceUrl: "https://fixture.invalid/#" + $0, exploreUrl: menu) }
        let store = SourceStore(persistence: SourcePersistence(rootURL: root), preloadedSources: .success(.init(sources: sources)))
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root), groupPersistence: BookshelfGroupPersistence(rootURL: root))
        let engine = BrowseFixture(failsOnce: failsOnce)
        return (AppState(sourceStore: store, bookshelfStore: shelf, engine: engine), defaults, engine)
    }
}

private actor BrowseFixture: SourceEngine {
    private(set) var menus: [String] = []
    private(set) var pages: [Int] = []
    let failsOnce: Bool
    init(failsOnce: Bool) { self.failsOnce = failsOnce }

    func exploreMenu(source: BookSource) async -> Result<SourceExploreMenu, SourceEngineError> {
        menus.append(source.bookSourceName)
        if failsOnce && menus.count == 1 { return .failure(.network("offline menu")) }
        return .success(.init(categories: ExploreCategoryParser.parse(exploreUrl: source.exploreUrl), controls: []))
    }

    func exploreBooks(source: BookSource, url: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        let fail = failsOnce && page == 2 && !pages.contains(2)
        pages.append(page)
        if fail { return .failure(.network("offline page two")) }
        let book = SearchBook(name: String(page), author: nil, coverUrl: nil, bookUrl: url + "/\(page)",
            sourceName: source.bookSourceName, sourceUrl: source.id)
        return .success(page <= 2 ? [book, book] : [])
    }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> { .failure(.unsupported("fixture")) }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> { .failure(.unsupported("fixture")) }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> { .failure(.unsupported("fixture")) }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> { .failure(.unsupported("fixture")) }
    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> { .failure(.unsupported("fixture")) }
}
