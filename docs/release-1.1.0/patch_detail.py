from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
p=ROOT/'SourceReadSwift/Features/Discover/BookDetailView.swift';s=p.read_text(encoding='utf8')
s=s.replace('    @State private var isLoading = false','    @State private var loadGeneration = UUID()\n    @State private var tocExpansionTask: Task<Void, Never>?\n    @State private var isLoading = false',1)
start=s.index('    private func refreshDetailAndTOC(');end=s.index('    private func reload()',start)
s=s[:start]+'''    private enum LoadEvent {
        case detail(Result<BookDetail, SourceEngineError>)
        case toc(Result<[BookChapter], SourceEngineError>)
    }

    private func refreshDetailAndTOC(source: BookSource, reportErrors: Bool) async {
        let engine = appState.engine
        let selectedBook = book
        let generation = UUID()
        loadGeneration = generation
        tocExpansionTask?.cancel()
        let stagedFirstPaint = chapters.isEmpty
        let placeholder = BookDetail(name: selectedBook.name, author: selectedBook.author,
            coverUrl: selectedBook.coverUrl, bookUrl: selectedBook.bookUrl, tocUrl: nil,
            sourceName: selectedBook.sourceName, sourceUrl: selectedBook.sourceUrl,
            intro: selectedBook.intro, latestChapter: selectedBook.lastChapter,
            wordCount: selectedBook.wordCount, kind: selectedBook.kind)
        let pages = stagedFirstPaint ? 1 : 30
        var fetchedDetail: BookDetail?
        var tocFailed = false
        func current() -> Bool {
            !Task.isCancelled && loadGeneration == generation
                && book.bookUrl == selectedBook.bookUrl && book.sourceUrl == selectedBook.sourceUrl
        }
        // Deliver each phase as it arrives. A fast TOC must not wait behind a
        // slow metadata request just because detailTask was awaited first.
        await withTaskGroup(of: LoadEvent.self) { group in
            group.addTask {
                .detail(await AsyncTimeout.run(seconds: 20) {
                    await engine.getBookDetail(source: source, book: selectedBook)
                } ?? .failure(.network("详情加载超时")))
            }
            group.addTask {
                .toc(await AsyncTimeout.run(seconds: 12) {
                    await engine.getChapterList(source: source, book: placeholder, maxPages: pages)
                } ?? .failure(.network("目录加载超时")))
            }
            for await event in group {
                guard current() else { group.cancelAll(); return }
                switch event {
                case .detail(.success(let value)):
                    fetchedDetail = value
                    detail = value
                    isLoading = false
                    if book.coverUrl?.nilIfEmpty == nil, let cover = value.coverUrl?.nilIfEmpty {
                        book = SearchBook(name: book.name, author: book.author ?? value.author,
                            coverUrl: cover, bookUrl: book.bookUrl, sourceName: book.sourceName,
                            sourceUrl: book.sourceUrl, intro: book.intro ?? value.intro,
                            kind: book.kind, lastChapter: book.lastChapter,
                            wordCount: book.wordCount, checkKeyWord: book.checkKeyWord)
                    }
                case .detail(.failure(let error)):
                    if reportErrors && chapters.isEmpty { errorMessage = error.displayMessage }
                case .toc(.success(let value)):
                    chapters = value
                    isLoading = false
                    errorMessage = nil
                case .toc(.failure):
                    tocFailed = true
                }
            }
        }
        guard current() else { return }
        // Some rules need the real tocUrl/variables obtained from metadata.
        if tocFailed, let fetchedDetail {
            let retry = await AsyncTimeout.run(seconds: 20) {
                await engine.getChapterList(source: source, book: fetchedDetail, maxPages: pages)
            }
            guard current() else { return }
            if case .success(let value) = retry { chapters = value; errorMessage = nil }
            else if reportErrors && chapters.isEmpty { errorMessage = "目录加载失败，可刷新重试" }
        }
        guard current() else { return }
        isLoading = false
        let cacheDetail = fetchedDetail ?? placeholder
        if detail == nil { detail = cacheDetail }
        if !chapters.isEmpty {
            appState.bookTOCacheStore.save(detail: cacheDetail, chapters: chapters,
                sourceURL: selectedBook.sourceUrl, bookURL: selectedBook.bookUrl)
            if stagedFirstPaint { extendTOCInBackground(source: source, detail: cacheDetail, generation: generation) }
        }
    }

    private func extendTOCInBackground(source: BookSource, detail loadedDetail: BookDetail, generation: UUID) {
        let engine = appState.engine
        let bookURL = book.bookUrl
        let sourceURL = book.sourceUrl
        tocExpansionTask = Task { @MainActor in
            let result = await engine.getChapterList(source: source, book: loadedDetail)
            guard !Task.isCancelled, loadGeneration == generation,
                  book.bookUrl == bookURL, book.sourceUrl == sourceURL,
                  case .success(let full) = result, full.count > chapters.count else { return }
            chapters = full
            appState.bookTOCacheStore.save(detail: loadedDetail, chapters: full,
                sourceURL: sourceURL, bookURL: bookURL)
        }
    }

''' + s[end:]
p.write_text(s,encoding='utf8')
