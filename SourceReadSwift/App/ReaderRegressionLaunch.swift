import Foundation

/// Debug UI tests use real shelf/reader flows with an isolated local-book store.
@MainActor enum ReaderRegressionLaunch {
    static func makeAppState() -> AppState {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--floating-desk-regression") {
            return FloatingDeskRegressionLaunch.makeAppState()
        }
        if ProcessInfo.processInfo.arguments.contains("--reader-preview-regression") {
            return ReaderPreviewRegressionFixture.makeAppState()
        }
        if ProcessInfo.processInfo.arguments.contains("--reader-settings-regression") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-ui-" + UUID().uuidString)
            let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root),
                groupPersistence: BookshelfGroupPersistence(rootURL: root))
            shelf.addLocalTextBook(OnboardingClassicBook.makeWelcomeBook())
            return AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: root)), bookshelfStore: shelf)
        }
        #endif
        return AppState()
    }
}

#if DEBUG
private struct ReaderPreviewRegressionFixture: SourceEngine {
    private static let origin = "https://preview-fixture.invalid"
    private static let title = "Preview · 未入架阅读样本"

    @MainActor static func makeAppState() -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("reader-preview-ui-" + UUID().uuidString)
        let sources = SourceStore(persistence: SourcePersistence(rootURL: root))
        do {
            try sources.importSources([BookSource(bookSourceName: "离线测试源", bookSourceUrl: origin, searchUrl: origin + "/search")])
        } catch {
            assertionFailure("Could not install the isolated reader source: \(error.localizedDescription)")
        }
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root),
            groupPersistence: BookshelfGroupPersistence(rootURL: root))
        return AppState(sourceStore: sources, bookshelfStore: shelf,
            chapterContentCacheStore: ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root)),
            bookTOCacheStore: BookTOCacheStore(rootURL: root),
            readingHistoryStore: ReadingHistoryStore(persistence: ReadingHistoryPersistence(rootURL: root)), engine: Self())
    }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        .success([.init(name: Self.title, author: "纸间", coverUrl: nil, bookUrl: Self.origin + "/book",
                        sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)])
    }

    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        .success(.init(name: book.name, author: book.author, coverUrl: nil, bookUrl: book.bookUrl,
                       sourceName: book.sourceName, sourceUrl: book.sourceUrl, intro: "测试首次阅读与退出保留的位置。", latestChapter: "阅读试章"))
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        .success([.init(title: "阅读试章", url: book.bookUrl + "/chapter", bookUrl: book.bookUrl, index: 0)])
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        .success(.init(chapter: chapter, title: chapter.title, paragraphs: (1...25).map {
            "【试读段落\($0)】" + String(repeating: "这里是可以滚动并保存的隔离测试文字。", count: 8)
        }, nextContentUrl: nil))
    }

    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .success(.init(status: .notConfigured, message: "隔离测试无需登录", cookiePresent: false))
    }
}
#endif
