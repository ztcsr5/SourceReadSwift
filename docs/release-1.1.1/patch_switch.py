from pathlib import Path
R=Path(__file__).resolve().parents[2]
def edit(name,fn):
 p=R/name;s=p.read_text(encoding='utf-8');t=fn(s);assert t!=s,name;p.write_text(t,encoding='utf-8')
def once(s,a,b):
 assert s.count(a)==1,(a[:90],s.count(a));return s.replace(a,b,1)

def cache(s):
 s=once(s,'        var book: SearchBook','        var book: SearchBook\n        var chapterCount: Int? = nil')
 s=once(s,'    private let fileURL: URL','    private static let writer = DispatchQueue(label: "SourceSwitchCache.writer", qos: .utility)\n    private let fileURL: URL')
 s=once(s,'        guard let data = try? Data(contentsOf: fileURL) else { return }','        guard let data = Self.writer.sync(execute: { try? Data(contentsOf: fileURL) }) else { return }')
 s=once(s,'        guard let data = try? JSONEncoder().encode(entries) else { return }\n        try? AppStorageDirectory.safeWrite(data, to: fileURL)','        let snapshot = entries\n        let url = fileURL\n        Self.writer.async {\n            guard let data = try? JSONEncoder().encode(snapshot) else { return }\n            try? AppStorageDirectory.safeWrite(data, to: url)\n        }')
 i=s.index('    func clear()');s=s[:i]+'''    func remember(books: [SearchBook]) {
        let grouped = Dictionary(grouping: books) { Self.key(title: $0.name, author: $0.author) }
        for (_, books) in grouped {
            guard let first = books.first else { continue }
            var items = candidates(title: first.name, author: first.author) ?? []
            for book in books where !book.sourceUrl.hasPrefix("local://") {
                if !items.contains(where: { $0.sourceURL == book.sourceUrl && $0.book.bookUrl == book.bookUrl }) {
                    items.append(Candidate(sourceURL: book.sourceUrl, sourceName: book.sourceName, book: book))
                }
            }
            save(title: first.name, author: first.author, candidates: items)
        }
    }

'''+s[i:];return s
if 'func remember(books:' not in (R/'SourceReadSwift/Core/Storage/SourceSwitchCacheStore.swift').read_text(encoding='utf-8'):
 edit('SourceReadSwift/Core/Storage/SourceSwitchCacheStore.swift',cache)
edit('SourceReadSwift/Features/Discover/BookDetailView.swift',lambda s:s.replace('        .task {\n            await load()','        .task {\n            SourceSwitchCacheStore.shared.remember(books: availableSources + [book])\n            await load()',1))

def gateway(s):
 s=once(s,'    @State private var sourceSwitchSearchTrigger = 0','''    @State private var sourceSwitchSearchTrigger = 0
    @State private var sourceSwitchGeneration = UUID()
    @State private var sourceSwitchApplyTask: Task<Void, Never>?
    @State private var isApplyingSource = false
    @State private var switchRefreshRequested = false''')
 s=once(s,'.sheet(isPresented: $showSourceSwitcher)', '.fullScreenCover(isPresented: $showSourceSwitcher)')
 a=s.index('                    extraToolbarActions: {');b=s.index('                    onRequestSourceSwitch:',a)
 s=s[:a]+s[b:]
 s=once(s,'Task { await applySwitch(candidate) }','''sourceSwitchGeneration = UUID()
                                sourceSwitchSearchTrigger &+= 1
                                isApplyingSource = true
                                sourceSwitchState.isLoading = false
                                sourceSwitchApplyTask?.cancel()
                                sourceSwitchApplyTask = Task { await applySwitch(candidate) }''')
 s=once(s,'                                    Text(candidate.book.bookUrl)','''                                    Text(candidate.chapterCount.map { "共 \\($0) 章" } ?? "章节数待统计")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text(candidate.book.bookUrl)''')
 s=once(s,'.disabled(sourceSwitchState.isLoading && sourceSwitchState.candidates.isEmpty)', '.disabled(isApplyingSource)')
 s=once(s,'                if sourceSwitchState.isLoading, sourceSwitchState.candidates.isEmpty {','''                if isApplyingSource {
                    ProgressView("正在对齐阅读章节…").padding(.horizontal)
                }
                if let message = sourceSwitchState.message, !sourceSwitchState.candidates.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                if sourceSwitchState.isLoading, sourceSwitchState.candidates.isEmpty {''')
 s=once(s,'                } else if let message = sourceSwitchState.message {','                } else if let message = sourceSwitchState.message, sourceSwitchState.candidates.isEmpty {')
 s=once(s,'                    Button("搜索") {\n                        sourceSwitchState = SourceSwitchState()','                    Button("刷新") {\n                        switchRefreshRequested = true\n                        sourceSwitchGeneration = UUID()\n                        sourceSwitchState.message = nil')
 s=once(s,'.disabled(sourceSwitchState.isLoading)', '.disabled(isApplyingSource || sourceSwitchState.isLoading)')
 a=s.index('            .task(id: sourceSwitchSearchTrigger)');b=s.index('\n    private var sourceSwitchProgressTitle',a)
 s=s[:a]+'''            .task(id: sourceSwitchSearchTrigger) {
                guard !isApplyingSource else { return }
                if sourceSwitchState.candidates.isEmpty || switchRefreshRequested {
                    await searchSwitchCandidates(force: switchRefreshRequested)
                }
            }
        }
        .interactiveDismissDisabled(isApplyingSource)
        .onDisappear {
            sourceSwitchGeneration = UUID()
            sourceSwitchApplyTask?.cancel()
            isApplyingSource = false
            sourceSwitchState.isLoading = false
            // Keep partial candidates; closing a search is not cache invalidation.
        }
    }
'''+s[b:]
 a=s.index('    private func searchSwitchCandidates()');b=s.index('    private func applySwitch(',a)
 s=s[:a]+'''    private func persistSwitchCandidates() {
        let active = currentBook
        SourceSwitchCacheStore.shared.save(title: active.title, author: active.author,
            candidates: sourceSwitchState.candidates.map {
                SourceSwitchCacheStore.Candidate(sourceURL: $0.source.bookSourceUrl,
                    sourceName: $0.source.bookSourceName, book: $0.book, chapterCount: $0.chapterCount)
            })
    }

    private func searchSwitchCandidates(force: Bool = false) async {
        let active = currentBook
        let kind = appState.sourceStore.source(for: active.sourceURL)?.sourceKind
        let sources = Array(appState.sourceStore.sourceSwitchCandidates(for: active.bookURL, excluding: active.sourceURL)
            .filter { kind == nil || $0.sourceKind == kind }.prefix(60))
        if !force, let cached = SourceSwitchCacheStore.shared.candidates(title: active.title, author: active.author) {
            sourceSwitchState.candidates = cached.compactMap { entry in
                guard entry.sourceURL != active.sourceURL,
                      let source = appState.sourceStore.source(for: entry.sourceURL), source.enabled,
                      kind == nil || source.sourceKind == kind else { return nil }
                return SourceSwitchCandidate(source: source, book: entry.book, chapterCount: entry.chapterCount)
            }
            // A fresh cache opens without triggering another search. Refresh is explicit.
            if !sourceSwitchState.candidates.isEmpty { return }
        }
        let token = UUID(); sourceSwitchGeneration = token
        switchRefreshRequested = false
        sourceSwitchState.isLoading = true
        sourceSwitchState.totalCount = sources.count
        sourceSwitchState.checkedCount = 0
        sourceSwitchState.message = nil
        let engine = appState.engine
        await withTaskGroup(of: Void.self) { group in
            var iterator = sources.makeIterator()
            func submit(_ source: BookSource) {
                group.addTask {
                    let result = await AsyncTimeout.run(seconds: 8) {
                        await engine.searchBooks(source: source, keyword: active.title, page: 1)
                    }
                    guard !Task.isCancelled, case .success(let books) = result,
                          let match = books.first(where: {
                              SearchBookMatcher.cleanTitle($0.name) == SearchBookMatcher.cleanTitle(active.title)
                                && (SearchBookMatcher.cleanAuthor($0.author ?? "").isEmpty
                                    || SearchBookMatcher.cleanAuthor(active.author).isEmpty
                                    || SearchBookMatcher.cleanAuthor($0.author ?? "") == SearchBookMatcher.cleanAuthor(active.author))
                          }) else { return }
                    let candidate = SourceSwitchCandidate(source: source, book: match)
                    let accepted = await MainActor.run { () -> Bool in
                        guard sourceSwitchGeneration == token, !isApplyingSource else { return false }
                        if !sourceSwitchState.candidates.contains(where: { $0.id == candidate.id }) {
                            sourceSwitchState.candidates.append(candidate)
                        }
                        persistSwitchCandidates()
                        return true
                    }
                    guard accepted else { return }
                    // Count the real full TOC, not the latest chapter's number.
                    let cached = await MainActor.run {
                        appState.bookTOCacheStore.entry(sourceURL: source.bookSourceUrl, bookURL: match.bookUrl)
                    }
                    var count = cached?.chapters.count
                    if count == nil {
                        let metadata = await AsyncTimeout.run(seconds: 12) {
                            let detailResult = await engine.getBookDetail(source: source, book: match)
                            guard case .success(let detail) = detailResult else { return (nil as BookDetail?, [BookChapter]()) }
                            let toc = await engine.getChapterList(source: source, book: detail)
                            return (detail as BookDetail?, (try? toc.get()) ?? [])
                        }
                        if let metadata, !metadata.1.isEmpty {
                            count = metadata.1.count
                            await MainActor.run {
                                guard sourceSwitchGeneration == token else { return }
                                appState.bookTOCacheStore.save(detail: metadata.0, chapters: metadata.1,
                                    sourceURL: source.bookSourceUrl, bookURL: match.bookUrl)
                            }
                        }
                    }
                    guard !Task.isCancelled else { return }
                    let resolvedCount = count
                    await MainActor.run {
                        guard sourceSwitchGeneration == token, !isApplyingSource,
                              let i = sourceSwitchState.candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
                        sourceSwitchState.candidates[i].chapterCount = resolvedCount
                        persistSwitchCandidates()
                    }
                }
            }
            for _ in 0..<min(6, sources.count) { if let source = iterator.next() { submit(source) } }
            while await group.next() != nil {
                guard !Task.isCancelled, sourceSwitchGeneration == token, !isApplyingSource else { group.cancelAll(); break }
                sourceSwitchState.checkedCount += 1
                if let source = iterator.next() { submit(source) }
            }
        }
        guard !Task.isCancelled, sourceSwitchGeneration == token, !isApplyingSource else { return }
        sourceSwitchState.isLoading = false
        if sourceSwitchState.candidates.isEmpty { sourceSwitchState.message = "没有找到同名同作者结果，可刷新重试。" }
    }

'''+s[b:]
 a=s.index('    private func applySwitch(');b=s.index('\n}\n\nprivate struct SourceSwitchState',a)
 s=s[:a]+'''    private func applySwitch(_ candidate: SourceSwitchCandidate) async {
        let token = sourceSwitchGeneration
        let progress = currentBook
        defer { if sourceSwitchGeneration == token { isApplyingSource = false } }
        persistSwitchCandidates()
        let cached = appState.bookTOCacheStore.entry(sourceURL: candidate.source.bookSourceUrl, bookURL: candidate.book.bookUrl)
        let engine = appState.engine
        let loaded: (BookDetail, [BookChapter])?
        if let detail = cached?.detail, let chapters = cached?.chapters, !chapters.isEmpty {
            loaded = (detail, chapters)
        } else {
            loaded = await AsyncTimeout.run(seconds: 24) {
                guard case .success(let detail) = await engine.getBookDetail(source: candidate.source, book: candidate.book),
                      case .success(let chapters) = await engine.getChapterList(source: candidate.source, book: detail),
                      !chapters.isEmpty else { return nil as (BookDetail, [BookChapter])? }
                return (detail, chapters)
            } ?? nil
        }
        guard !Task.isCancelled, sourceSwitchGeneration == token, showSourceSwitcher else { return }
        guard let (newDetail, newChapters) = loaded,
              let target = SourceChapterAlignment.match(title: progress.currentChapterTitle,
                  index: progress.currentChapterIndex, in: newChapters) else {
            sourceSwitchState.message = "无法读取该源目录，阅读进度未改变；请选择其他源或重试。"
            return
        }
        appState.bookTOCacheStore.save(detail: newDetail, chapters: newChapters,
            sourceURL: candidate.source.bookSourceUrl, bookURL: candidate.book.bookUrl)
        appState.bookshelfStore.switchSource(bookID: book.id, to: candidate.book,
            latestChapterTitle: newDetail.latestChapter ?? newChapters.last?.title,
            intro: newDetail.intro, totalChapters: newChapters.count)
        appState.bookshelfStore.updateReadingProgress(bookID: book.id, chapterIndex: target.index,
            chapterTitle: target.title, totalChapters: newChapters.count, paragraphIndex: 0)
        detail = newDetail
        chapters = newChapters
        selectedChapter = target
        errorMessage = nil
        showSourceSwitcher = false
    }
'''+s[b:]
 s=once(s,'    let book: SearchBook\n}', '    let book: SearchBook\n    var chapterCount: Int? = nil\n}')
 return s
edit('SourceReadSwift/Features/Bookshelf/BookshelfReaderGatewayView.swift',gateway)
print('source switch patched')
