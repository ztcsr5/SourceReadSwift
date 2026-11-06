import Foundation

/// Adapts an imported local comic to the existing manga reader without network IO.
struct LocalComicSourceEngine: SourceEngine {
    let book: BookshelfBook

    static var source: BookSource {
        BookSource(bookSourceName: "本地漫画", bookSourceUrl: "local://comic", bookSourceType: 2)
    }

    var chapters: [BookChapter] {
        (book.localChapters ?? []).map {
            BookChapter(title: $0.title, url: "localcomic://chapter/\($0.index)",
                        bookUrl: book.bookURL, index: $0.index)
        }
    }

    /// Only the local engine resolves file URLs; network rules remain HTTP-only.
    func pages(for chapter: BookChapter) -> [ComicPage] {
        guard chapter.bookUrl == book.bookURL,
              let local = book.localChapters?.first(where: { $0.index == chapter.index }) else { return [] }
        return local.paragraphs.enumerated().compactMap { index, paragraph in
            guard paragraph.hasPrefix("[img]"), paragraph.hasSuffix("[/img]"),
                  let address = URL(string: String(paragraph.dropFirst(5).dropLast(6))), address.isFileURL else { return nil }
            return ComicPage(id: index, url: address.absoluteString)
        }
    }

    func searchBooks(source: BookSource, keyword: String, page: Int) async -> Result<[SearchBook], SourceEngineError> {
        .failure(.unsupported("本地漫画不使用网络搜索。"))
    }

    func getBookDetail(source: BookSource, book requestedBook: SearchBook) async -> Result<BookDetail, SourceEngineError> {
        .success(BookDetail(name: book.title, author: book.author, coverUrl: book.coverURL,
            bookUrl: book.bookURL, sourceName: source.bookSourceName, sourceUrl: source.bookSourceUrl,
            intro: book.intro, latestChapter: chapters.last?.title))
    }

    func getChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        .success(chapters)
    }

    func getCompleteChapterList(source: BookSource, book: BookDetail) async -> Result<[BookChapter], SourceEngineError> {
        .success(chapters)
    }

    func getContent(source: BookSource, chapter: BookChapter) async -> Result<ChapterContent, SourceEngineError> {
        guard chapter.bookUrl == book.bookURL,
              let local = book.localChapters?.first(where: { $0.index == chapter.index }) else {
            return .failure(.empty("本地漫画章节不存在，请返回书架重新导入。"))
        }
        return .success(ChapterContent(chapter: chapter, title: local.title, paragraphs: local.paragraphs))
    }

    func verifyLogin(source: BookSource) async -> Result<SourceLoginVerification, SourceEngineError> {
        .success(.init(status: .notConfigured, message: "本地漫画无需登录。", cookiePresent: false))
    }
}
