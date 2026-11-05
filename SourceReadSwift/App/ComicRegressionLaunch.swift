#if DEBUG
import UIKit

/// Isolated UI-test inputs exercising the production comic reader without external websites.
@MainActor enum ComicRegressionLaunch {
    static func makeAppState() -> AppState {
        let arguments = ProcessInfo.processInfo.arguments
        let session = arguments.firstIndex(of: "--comic-reader-session").flatMap { index in
            arguments.indices.contains(index + 1) ? UUID(uuidString: arguments[index + 1]) : nil
        } ?? UUID()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("comic-ui-" + session.uuidString)
        let isOffline = arguments.contains("--comic-reader-source-unavailable")
        if !FileManager.default.fileExists(atPath: root.path) {
            UserDefaults.standard.set(ComicReadingMode.vertical.rawValue, forKey: "comic.readingMode")
        }
        let source = BookSource(bookSourceName: "漫画测试源", bookSourceUrl: ComicRegressionEngine.origin,
                                bookSourceType: 2, searchUrl: ComicRegressionEngine.origin + "/search")
        let sources = SourceStore(persistence: SourcePersistence(rootURL: root))
        do { try sources.importSources([source]) }
        catch { assertionFailure("Comic fixture source import failed: \(error.localizedDescription)") }
        let pageIndices = isOffline ? [] : Array(0..<6)
        let images: [String] = pageIndices.compactMap { index in
            let height: CGFloat = index.isMultiple(of: 2) ? 960 : 540
            let artwork = UIGraphicsImageRenderer(size: CGSize(width: 390, height: height)).image { renderer in
                UIColor(white: index.isMultiple(of: 2) ? 0.92 : 0.75, alpha: 1).setFill()
                renderer.fill(CGRect(x: 0, y: 0, width: 390, height: height))
                let label = "Comic · 第 \(index + 1) 页" as NSString
                label.draw(at: CGPoint(x: 24, y: 32),
                           withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
                for line in 1..<8 {
                    let caption = "真实图片加载、原生滚动和缩放测试 · \(line)" as NSString
                    caption.draw(at: CGPoint(x: 24, y: CGFloat(line) * 100),
                                 withAttributes: [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.darkGray])
                }
            }
            guard let png = artwork.pngData() else { return nil }
            return InlineImageStore.shared.store(.init(data: png, fileExtension: "png"))?.absoluteString
        }
        return AppState(sourceStore: sources,
            bookshelfStore: BookshelfStore(persistence: BookshelfPersistence(rootURL: root),
                                           groupPersistence: BookshelfGroupPersistence(rootURL: root)),
            chapterContentCacheStore: ChapterContentCacheStore(persistence: ChapterContentCachePersistence(rootURL: root)),
            bookTOCacheStore: BookTOCacheStore(rootURL: root),
            chapterDownloadStore: ChapterDownloadStore(persistence: ChapterDownloadPersistence(rootURL: root)),
            readingHistoryStore: ReadingHistoryStore(persistence: ReadingHistoryPersistence(rootURL: root)),
            engine: ComicRegressionEngine(images: images),
            comicOfflineArchive: ComicOfflineArchive(directory: root.appendingPathComponent("OfflineComics")))
    }
}

private struct ComicRegressionEngine: SourceEngine {
    static let origin = "https://comic-reader-fixture.invalid"
    let images: [String]
    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        guard !images.isEmpty else { return .failure(.network("测试书源已断开")) }
        return .success([.init(name: "Comic · 图片阅读样本", author: "纸间", coverUrl: nil,
                        bookUrl: Self.origin + "/book", sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl)])
    }
    func getBookDetail(source: BookSource, book: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        guard !images.isEmpty else { return .failure(.network("测试书源已断开")) }
        return .success(.init(name: book.name, author: book.author, coverUrl: nil, bookUrl: book.bookUrl,
                       sourceName: book.sourceName, sourceUrl: book.sourceUrl, intro: "本地夹具，不影响普通书源。", latestChapter: "第二话"))
    }
    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        guard !images.isEmpty else { return .failure(.network("测试书源已断开")) }
        return .success((0..<2).map { .init(title: "第\($0 + 1)话", url: Self.origin + "/chapter/\($0)", bookUrl: book.bookUrl, index: $0) })
    }
    func getCompleteChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        await getChapterList(source: source, book: book)
    }
    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        guard !images.isEmpty else { return .failure(.network("测试书源已断开")) }
        return .success(.init(chapter: chapter, title: chapter.title, paragraphs: images.map { "[img]\($0)[/img]" }))
    }
}
#endif
