import SwiftUI

struct BookshelfReaderGatewayView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let book: BookshelfBook
    var initialBookmark: ReaderBookmark? = nil
    var initialChapterIndex: Int? = nil

    @State private var detail: BookDetail?
    @State private var chapters: [BookChapter] = []
    @State private var selectedChapter: BookChapter?
    @State private var selectedLocalChapterIndex: Int?
    @State private var selectedLocalParagraphIndex: Int?
    @State private var errorMessage: String?
    @State private var showSourceSwitcher = false
    @State private var sourceSwitchState = SourceSwitchState()
    @State private var autoplaySpeechAfterHandoff = false
    @State private var autoplayAutoScrollAfterHandoff = false
    @State private var showReaderChromeAfterChapterSelection = false
    @State private var didApplyInitialBookmark = false
    @State private var didApplyInitialChapter = false
    @State private var requestedChapterIndex: Int?
    @State private var sourceSwitchSearchTrigger = 0
    @State private var localNavigationRevision = 0
    @State private var showBookDetailSheet = false
    @State private var gatewayTabChromeOwner = UUID()
    @State private var initialLocalChapterSeed: Int?
    @State private var initialLocalParagraphSeed: Int?

    private var currentBook: BookshelfBook {
        appState.bookshelfStore.book(id: book.id) ?? book
    }

    var body: some View {
        gatewayContent
        .onAppear {
            appState.acquireTabChromeHidden(owner: gatewayTabChromeOwner)
            if initialLocalChapterSeed == nil {
                initialLocalChapterSeed = currentBook.currentChapterIndex
                initialLocalParagraphSeed = currentBook.currentParagraphIndex
            }
        }
        .onDisappear {
            appState.releaseTabChromeHidden(owner: gatewayTabChromeOwner)
        }
        .task {
            appState.bookshelfStore.markReaderOpened(bookID: book.id)
            appState.bookshelfStore.markUpdatesSeen(bookID: book.id)
            applyInitialBookmarkIfNeeded()
            applyInitialChapterIfNeeded()
            await resumeReading()
        }
        .sheet(isPresented: $showSourceSwitcher) {
            sourceSwitcherSheet
        }
        .sheet(isPresented: $showBookDetailSheet) {
            NavigationStack {
                BookDetailView(book: currentBook.asSearchBook)
            }
        }
    }

    private var gatewayContent: AnyView {
        if !localBookChapters.isEmpty {
            return AnyView(localReader)
        } else if let localContent = book.localContent {
            return AnyView(
                ReaderView(
                    bookID: book.id,
                    content: ChapterContent(
                        chapter: BookChapter(title: "全文", url: book.bookURL, bookUrl: book.bookURL, index: 0, isVip: false),
                        title: book.title,
                        paragraphs: localContent,
                        nextContentUrl: nil
                    ),
                    chapterIndex: 0,
                    totalChapters: 1
                )
            )
        } else if let selectedChapter {
            if let source = appState.sourceStore.source(for: currentBook.sourceURL) {
                switch source.sourceKind {
                case .audio:
                    return AnyView(
                        AudioBookPlayerView()
                            .onAppear {
                                let searchBook = SearchBook(
                                    name: currentBook.title,
                                    author: currentBook.author,
                                    coverUrl: currentBook.coverURL,
                                    bookUrl: currentBook.bookURL,
                                    sourceName: source.bookSourceName,
                                    sourceUrl: source.bookSourceUrl
                                )
                                AudioBookPlaybackCoordinator.shared.startBook(
                                    bookID: currentBook.id,
                                    book: searchBook,
                                    source: source,
                                    chapters: chapters,
                                    initialChapterIndex: selectedChapter.index,
                                    initialPositionSeconds: currentBook.currentParagraphIndex.map { Double($0) },
                                    engine: appState.engine,
                                    bookshelfStore: appState.bookshelfStore
                                )
                            }
                    )
                case .comic:
                    return AnyView(
                        ComicReaderView(
                            bookID: book.id,
                            bookTitle: currentBook.title,
                            source: source,
                            initialChapterIndex: selectedChapter.index,
                            chapters: chapters,
                            engine: appState.engine
                        )
                    )
                case .video:
                    return AnyView(
                        VideoPlayerView(
                            bookID: book.id,
                            bookTitle: currentBook.title,
                            source: source,
                            initialChapterIndex: selectedChapter.index,
                            initialPositionSeconds: currentBook.currentParagraphIndex.map { Double($0) },
                            chapters: chapters,
                            engine: appState.engine
                        )
                    )
                case .text:
                    break
                }
            }
            let storedParagraph = currentBook.currentChapterIndex == selectedChapter.index ? currentBook.currentParagraphIndex : nil
            return AnyView(
                ChapterLoadingView(
                    bookID: book.id,
                    sourceUrl: currentBook.sourceURL,
                    chapter: selectedChapter,
                    totalChapters: chapters.count,
                    chapters: chapters,
                    initialParagraphIndex: storedParagraph,
                    extraToolbarActions: {
                        AnyView(
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showSourceSwitcher = true
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.title3.weight(.semibold))
                                    .frame(width: 44, height: 44)
                            }
                        )
                    },
                    onRequestSourceSwitch: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showSourceSwitcher = true
                    },
                    onRequestBookDetail: {
                        showBookDetailSheet = true
                    }
                )
            )
        } else if let errorMessage {
            return AnyView(readerRecoveryErrorView(errorMessage))
        } else {
            return AnyView(
                ProgressView("正在恢复阅读进度")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .pageBackground()
            )
        }
    }

    private var localBookChapters: [LocalTextChapter] {
        book.localChapters ?? []
    }

    private var localNavigationEntries: [LocalTextNavigationEntry] {
        currentBook.localNavigationEntries ?? []
    }

    private func applyInitialBookmarkIfNeeded() {
        guard !didApplyInitialBookmark, let initialBookmark else { return }
        didApplyInitialBookmark = true
        if !localBookChapters.isEmpty {
            selectedLocalChapterIndex = initialBookmark.chapterIndex
        }
        appState.bookshelfStore.updateReadingProgress(
            bookID: book.id,
            chapterIndex: initialBookmark.chapterIndex,
            chapterTitle: initialBookmark.chapterTitle,
            totalChapters: max(currentBook.totalChapters, initialBookmark.chapterIndex + 1),
            paragraphIndex: initialBookmark.paragraphIndex
        )
    }

    private func applyInitialChapterIfNeeded() {
        guard !didApplyInitialChapter, let initialChapterIndex else { return }
        didApplyInitialChapter = true
        requestedChapterIndex = max(0, initialChapterIndex)
    }

    private func readerRecoveryErrorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            EmptyStateCard(systemImage: "xmark.octagon", title: "阅读恢复失败", message: message)

            Button {
                showSourceSwitcher = true
            } label: {
                Label("尝试换源继续阅读", systemImage: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                errorMessage = nil
                selectedChapter = nil
                chapters = []
                Task { await resumeReading() }
            } label: {
                Label("重试当前书源", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(AppTheme.pagePadding)
        .pageBackground()
    }

    private var localReader: some View {
        let chapters = localBookChapters
        let requestedIndex = selectedLocalChapterIndex ?? requestedChapterIndex ?? initialLocalChapterSeed ?? currentBook.currentChapterIndex
        let safeIndex = min(max(requestedIndex, 0), max(chapters.count - 1, 0))
        let localChapter = chapters[safeIndex]
        let fallbackChapters = chapters.map {
            BookChapter(
                title: $0.title,
                url: "\(book.bookURL)#\($0.index)",
                bookUrl: book.bookURL,
                index: $0.index,
                isVip: false
            )
        }
        let storedParagraph = (initialLocalChapterSeed ?? currentBook.currentChapterIndex) == safeIndex
            ? (initialLocalParagraphSeed ?? currentBook.currentParagraphIndex)
            : nil
        let initialParagraphIndex = selectedLocalParagraphIndex ?? storedParagraph
        return ReaderView(
            bookID: book.id,
            content: ChapterContent(
                chapter: fallbackChapters[safeIndex],
                title: localChapter.title,
                paragraphs: localChapter.paragraphs,
                nextContentUrl: nil
            ),
            chapterIndex: safeIndex,
            totalChapters: chapters.count,
            chapters: fallbackChapters,
            navigationEntries: localNavigationEntries,
            initialParagraphIndex: initialParagraphIndex,
            onRequestBookDetail: {
                showBookDetailSheet = true
            },
            onSelectChapter: { chapter in
                showReaderChromeAfterChapterSelection = true
                selectedLocalChapterIndex = chapter.index
                selectedLocalParagraphIndex = nil
                localNavigationRevision &+= 1
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: chapter.index,
                    chapterTitle: chapter.title,
                    totalChapters: chapters.count
                )
            },
            onSelectChapterWithPosition: { chapter, targetParagraph in
                showReaderChromeAfterChapterSelection = true
                selectedLocalChapterIndex = chapter.index
                selectedLocalParagraphIndex = targetParagraph
                localNavigationRevision &+= 1
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: chapter.index,
                    chapterTitle: chapter.title,
                    totalChapters: chapters.count,
                    paragraphIndex: targetParagraph == Int.max ? nil : targetParagraph
                )
            },
            onSelectNavigationEntry: { entry in
                guard let chapterIndex = entry.chapterIndex, chapters.indices.contains(chapterIndex) else { return }
                showReaderChromeAfterChapterSelection = true
                selectedLocalChapterIndex = chapterIndex
                localNavigationRevision &+= 1
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: chapterIndex,
                    chapterTitle: entry.title,
                    totalChapters: chapters.count,
                    paragraphIndex: entry.paragraphIndex
                )
            },
            onSpeechFinished: {
                let nextIndex = safeIndex + 1
                guard chapters.indices.contains(nextIndex) else { return }
                autoplaySpeechAfterHandoff = true
                selectedLocalChapterIndex = nextIndex
                localNavigationRevision &+= 1
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: nextIndex,
                    chapterTitle: chapters[nextIndex].title,
                    totalChapters: chapters.count
                )
            },
            autoplaySpeechOnAppear: autoplaySpeechAfterHandoff,
            onSpeechAutoplayConsumed: {
                autoplaySpeechAfterHandoff = false
            },
            autoplayAutoScrollOnAppear: autoplayAutoScrollAfterHandoff,
            onAutoScrollAutoplayConsumed: {
                autoplayAutoScrollAfterHandoff = false
            },
            onAutoScrollFinished: {
                let nextIndex = safeIndex + 1
                guard chapters.indices.contains(nextIndex) else { return }
                autoplayAutoScrollAfterHandoff = true
                selectedLocalChapterIndex = nextIndex
                selectedLocalParagraphIndex = nil
                localNavigationRevision &+= 1
                appState.bookshelfStore.updateReadingProgress(
                    bookID: book.id,
                    chapterIndex: nextIndex,
                    chapterTitle: chapters[nextIndex].title,
                    totalChapters: chapters.count
                )
            },
            initialOverlayVisible: showReaderChromeAfterChapterSelection
        )
        .id("reader-\(book.id)")
    }

    /// 首章正文预热。
    ///
    /// 打开书籍时 TOC 有缓存并不代表正文有缓存（`cachedChapters` 只缓存章节列表）。
    /// 这里在点开书的一刻就把目标章正文取回来写进缓存，阅读器随后按
    /// `content(sourceURL:chapter:purifyRules:)` 查询即可命中，省掉首次打开的白等。
    /// 已有缓存直接返回；失败静默——预热失败不该在书架上弹任何东西。
    private func prefetchChapterContent(source: BookSource, chapter: BookChapter) {
        let rules = appState.purifyRuleStore.enabledPatterns
        guard !appState.chapterContentCacheStore.isCached(
            sourceURL: source.bookSourceUrl,
            chapter: chapter,
            purifyRules: rules
        ) else { return }
        Task.detached(priority: .userInitiated) { [appState, source, chapter] in
            guard let content = try? await appState.engine
                .getContent(source: source, chapter: chapter)
                .get()
            else { return }
            await MainActor.run {
                appState.chapterContentCacheStore.save(
                    content,
                    sourceURL: source.bookSourceUrl,
                    purifyRules: rules
                )
            }
        }
    }

    private func resumeReading() async {
        let activeBook = currentBook
        guard activeBook.localChapters == nil, activeBook.localContent == nil else { return }
        guard selectedChapter == nil, errorMessage == nil else { return }
        guard let source = appState.sourceStore.source(for: activeBook.sourceURL) else {
            errorMessage = "找不到书源：\(activeBook.sourceName)"
            return
        }

        // 0. TOC CACHE：上次成功落盘的完整目录。命中就立刻打开目标章，
        //    详情与目录在后台刷新——“点进书要等半天”卡的就是这里。
        if let cached = appState.bookTOCacheStore.entry(
            sourceURL: source.bookSourceUrl,
            bookURL: activeBook.bookURL
        ), !cached.chapters.isEmpty {
            let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
            let target = cached.chapters.first(where: { $0.index == targetIndex }) ?? cached.chapters.first
            if let target {
                chapters = cached.chapters
                if detail == nil { detail = cached.detail }
                selectedChapter = target
                prefetchChapterContent(source: source, chapter: target)
                refreshBookDetailAndTOC(source: source, book: activeBook)
                return
            }
        }

        // 1. FAST PATH: Instant-Open using cached chapters if available!
        let cached = appState.chapterContentCacheStore.cachedChapters(
            sourceURL: source.bookSourceUrl,
            bookURL: activeBook.bookURL
        )
        if !cached.isEmpty {
            let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
            let target = cached.first(where: { $0.index == targetIndex }) ?? cached.first
            if let target {
                self.chapters = cached
                self.selectedChapter = target
                // TOC 命中缓存 ≠ 正文命中缓存：首章正文在这里就发出去，
                // 阅读器打开时 content(...) 直接命中，不再白等一次网络。
                prefetchChapterContent(source: source, chapter: target)
                // Background silent refresh for new chapters and latest title.
                refreshBookDetailAndTOC(source: source, book: activeBook)
                return
            }
        }

        // 2. SLOW PATH: First time load when cache is empty
        let searchBook = SearchBook(
            name: activeBook.title,
            author: activeBook.author,
            coverUrl: activeBook.coverURL,
            bookUrl: activeBook.bookURL,
            sourceName: activeBook.sourceName,
            sourceUrl: activeBook.sourceURL,
            intro: activeBook.intro
        )

        let engine = appState.engine
        let detailResult = await AsyncTimeout.run(seconds: 20) {
            await engine.getBookDetail(source: source, book: searchBook)
        } ?? .failure(.network("Detail load timed out"))
        switch detailResult {
        case .success(let loadedDetail):
            detail = loadedDetail
            // 首次开书先取目录头部打开阅读器，完整目录交给后台刷新：
            // 分页目录是串行抓取，30 页会让「进书」停在加载页上。
            let chapterResult = await AsyncTimeout.run(seconds: 20) {
                await engine.getChapterList(source: source, book: loadedDetail, maxPages: 8)
            } ?? .failure(.network("Chapter list timed out"))
            switch chapterResult {
            case .success(let loadedChapters):
                chapters = loadedChapters
                appState.bookTOCacheStore.save(
                    detail: loadedDetail,
                    chapters: loadedChapters,
                    sourceURL: source.bookSourceUrl,
                    bookURL: activeBook.bookURL
                )
                let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
                let target = loadedChapters.first(where: { $0.index == targetIndex })
                    ?? loadedChapters.first
                if let target {
                    appState.bookshelfStore.updateDetails(
                        bookID: activeBook.id,
                        latestChapterTitle: loadedDetail.latestChapter,
                        intro: loadedDetail.intro,
                        totalChapters: loadedChapters.count,
                        coverURL: loadedDetail.coverUrl
                    )
                    selectedChapter = target
                    // 目录只取了前 8 页，阅读器已经打开，剩余章节后台补。
                    refreshBookDetailAndTOC(source: source, book: activeBook)
                } else {
                    errorMessage = "目录为空"
                }
            case .failure(let error):
                let cached = appState.chapterContentCacheStore.cachedChapters(
                    sourceURL: source.bookSourceUrl,
                    bookURL: activeBook.bookURL
                )
                let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
                if let target = cached.first(where: { $0.index == targetIndex }) ?? cached.first {
                    chapters = cached
                    selectedChapter = target
                    errorMessage = nil
                    appState.record(DiagnosticEvent(level: .info, stage: "reader.offline", sourceName: activeBook.sourceName, message: "目录网络失败，已切换到离线缓存", details: ["chapters": String(cached.count)]))
                } else {
                    errorMessage = "目录加载失败：\(error.displayMessage)"
                }
            }
        case .failure(let error):
            let cached = appState.chapterContentCacheStore.cachedChapters(
                sourceURL: source.bookSourceUrl,
                bookURL: activeBook.bookURL
            )
            let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
            if let target = cached.first(where: { $0.index == targetIndex }) ?? cached.first {
                chapters = cached
                selectedChapter = target
                errorMessage = nil
                appState.record(DiagnosticEvent(level: .info, stage: "reader.offline", sourceName: activeBook.sourceName, message: "详情网络失败，已切换到离线缓存", details: ["chapters": String(cached.count)]))
            } else {
                errorMessage = "详情加载失败：\(error.displayMessage)"
            }
        }
    }

    /// 后台补全详情与目录：命中本地目录缓存时先开书，新章节、最新标题和
    /// 封面在后台刷新，成功后再写回目录缓存。失败保持静默，不打断阅读。
    private func refreshBookDetailAndTOC(source: BookSource, book activeBook: BookshelfBook) {
        Task.detached(priority: .utility) { [appState, source, activeBook] in
            let searchBook = SearchBook(
                name: activeBook.title,
                author: activeBook.author,
                coverUrl: activeBook.coverURL,
                bookUrl: activeBook.bookURL,
                sourceName: activeBook.sourceName,
                sourceUrl: activeBook.sourceURL,
                intro: activeBook.intro
            )
            guard let detailResult = try? await appState.engine
                .getBookDetail(source: source, book: searchBook)
                .get()
            else { return }
            guard let loadedChapters = try? await appState.engine
                .getChapterList(source: source, book: detailResult)
                .get(),
                !loadedChapters.isEmpty
            else { return }
            await MainActor.run {
                self.detail = detailResult
                self.chapters = loadedChapters
                appState.bookTOCacheStore.save(
                    detail: detailResult,
                    chapters: loadedChapters,
                    sourceURL: source.bookSourceUrl,
                    bookURL: activeBook.bookURL
                )
                appState.bookshelfStore.updateDetails(
                    bookID: activeBook.id,
                    latestChapterTitle: detailResult.latestChapter,
                    intro: detailResult.intro,
                    totalChapters: loadedChapters.count,
                    coverURL: detailResult.coverUrl
                )
            }
        }
    }

    private var sourceSwitcherSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("搜索其他启用书源中的同名结果，选中后会保留当前书架项并切到新书源。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                if sourceSwitchState.isLoading, sourceSwitchState.candidates.isEmpty {
                    ProgressView(sourceSwitchProgressTitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = sourceSwitchState.message {
                    EmptyStateCard(systemImage: "magnifyingglass", title: "换源结果", message: message)
                        .padding(.horizontal)
                } else {
                    List {
                        if sourceSwitchState.isLoading {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text(sourceSwitchProgressTitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(sourceSwitchState.candidates) { candidate in
                            Button {
                                Task { await applySwitch(candidate) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.book.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(candidate.source.bookSourceName) · \(candidate.book.author ?? "作者未知")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(candidate.book.bookUrl)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                            }
                            .disabled(sourceSwitchState.isLoading && sourceSwitchState.candidates.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("关闭") { showSourceSwitcher = false }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("搜索") {
                        sourceSwitchState = SourceSwitchState()
                        sourceSwitchSearchTrigger &+= 1
                    }
                    .disabled(sourceSwitchState.isLoading)
                }
            }
            .task(id: sourceSwitchSearchTrigger) {
                if sourceSwitchState.candidates.isEmpty, sourceSwitchState.message == nil {
                    await searchSwitchCandidates()
                }
            }
        }
        .presentationDetents([.large])
        .onDisappear {
            // A dismissed sheet cancels its task. Clear a stale loading flag
            // so opening换源 again always starts a fresh search.
            if sourceSwitchState.isLoading {
                sourceSwitchState = SourceSwitchState()
            }
        }
    }

    private var sourceSwitchProgressTitle: String {
        guard sourceSwitchState.totalCount > 0 else { return "正在搜索可用换源" }
        return "正在搜索 \(sourceSwitchState.checkedCount)/\(sourceSwitchState.totalCount)"
    }

    private func searchSwitchCandidates() async {
        let activeBook = currentBook
        let enabledSources = Array(appState.sourceStore
            .sourceSwitchCandidates(for: activeBook.bookURL, excluding: activeBook.sourceURL)
            .prefix(40))

        // Show the previous result set immediately. The network refresh below
        // still runs, but the user can tap an already-known source without
        // waiting for 40 search requests again.
        var cachedCandidates: [SourceSwitchCandidate] = []
        if let cached = SourceSwitchCacheStore.shared.candidates(
            title: activeBook.title,
            author: activeBook.author
        ) {
            cachedCandidates = cached.compactMap { entry in
                guard let source = appState.sourceStore.source(for: entry.sourceURL) else { return nil }
                return SourceSwitchCandidate(source: source, book: entry.book)
            }
        }

        sourceSwitchState = SourceSwitchState(
            isLoading: true,
            candidates: cachedCandidates,
            totalCount: enabledSources.count
        )
        var candidates: [SourceSwitchCandidate] = cachedCandidates
        let engine = appState.engine
        // Keep source switching responsive without creating a burst of 40
        // simultaneous network requests. Six requests per batch is enough to
        // hide a slow source while preserving cancellation and device limits.
        let batchSize = 6
        for start in stride(from: 0, to: enabledSources.count, by: batchSize) {
            guard !Task.isCancelled else { return }
            let end = min(start + batchSize, enabledSources.count)
            let batch = Array(enabledSources[start..<end])
            let batchCandidates = await withTaskGroup(of: SourceSwitchCandidate?.self, returning: [SourceSwitchCandidate].self) { group in
                for source in batch {
                    group.addTask {
                        let result = await AsyncTimeout.run(seconds: 10) {
                            await engine.searchBooks(source: source, keyword: activeBook.title, page: 1)
                        } ?? .failure(.network("Source switch search timed out"))
                        guard case .success(let books) = result else { return nil }
                        let cleanTargetTitle = SearchBookMatcher.cleanTitle(activeBook.title)
                        let cleanTargetAuthor = SearchBookMatcher.cleanAuthor(activeBook.author)

                        func score(for b: SearchBook) -> Int {
                            let title = SearchBookMatcher.cleanTitle(b.name)
                            let author = SearchBookMatcher.cleanAuthor(b.author ?? "")
                            let isExactTitle = (title == cleanTargetTitle)
                            let isExactAuthor = (!cleanTargetAuthor.isEmpty && author == cleanTargetAuthor)

                            // Discard spinoff/fanfic noise keywords if original title did not have them
                            let noiseKeywords = ["同人", "续集", "前传", "后传", "外传", "之"]
                            let containsNoise = noiseKeywords.contains { k in
                                b.name.contains(k) && !activeBook.title.contains(k)
                            }
                            if containsNoise { return 0 }

                            if isExactTitle && isExactAuthor { return 100 }
                            if isExactTitle { return 80 }
                            if isExactAuthor && b.name.hasPrefix(activeBook.title) { return 60 }
                            if title == activeBook.title.lowercased() { return 70 }
                            return 0
                        }

                        let sortedMatches = books
                            .map { ($0, score(for: $0)) }
                            .filter { $0.1 > 0 }
                            .sorted { $0.1 > $1.1 }

                        guard let match = sortedMatches.first?.0 else { return nil }
                        return SourceSwitchCandidate(source: source, book: match)
                    }
                }
                var results: [SourceSwitchCandidate] = []
                results.reserveCapacity(batch.count)
                for await candidate in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return results
                    }
                    if let candidate { results.append(candidate) }
                }
                return results
            }
            for candidate in batchCandidates where !candidates.contains(where: { $0.id == candidate.id }) {
                candidates.append(candidate)
            }
            candidates.sort { $0.source.bookSourceName < $1.source.bookSourceName }
            sourceSwitchState = SourceSwitchState(
                isLoading: true,
                candidates: candidates,
                checkedCount: end,
                totalCount: enabledSources.count
            )
        }
        guard !Task.isCancelled else { return }
        candidates.sort { $0.source.bookSourceName < $1.source.bookSourceName }
        if !candidates.isEmpty {
            SourceSwitchCacheStore.shared.save(
                title: activeBook.title,
                author: activeBook.author,
                candidates: candidates.map {
                    SourceSwitchCacheStore.Candidate(
                        sourceURL: $0.source.bookSourceUrl,
                        sourceName: $0.source.bookSourceName,
                        book: $0.book
                    )
                }
            )
        }
        sourceSwitchState = candidates.isEmpty
            ? SourceSwitchState(message: "没有搜索到可用换源结果。")
            : SourceSwitchState(candidates: candidates)
    }

    private func applySwitch(_ candidate: SourceSwitchCandidate) async {
        sourceSwitchState.isLoading = true
        let engine = appState.engine
        let detailResult = await AsyncTimeout.run(seconds: 20) {
            await engine.getBookDetail(source: candidate.source, book: candidate.book)
        } ?? .failure(.network("Detail load timed out"))
        switch detailResult {
        case .success(let detail):
            let chapterResult = await AsyncTimeout.run(seconds: 20) {
                await engine.getChapterList(source: candidate.source, book: detail)
            } ?? .failure(.network("Chapter list timed out"))
            switch chapterResult {
            case .success(let loadedChapters):
                let previousTitle = (selectedChapter?.title ?? currentBook.currentChapterTitle ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                let previousIndex = selectedChapter?.index ?? currentBook.currentChapterIndex
                let matchedByTitle = previousTitle.isEmpty ? nil : loadedChapters.first(where: {
                    $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == previousTitle
                })
                let clampedIndex = min(max(previousIndex, 0), max(loadedChapters.count - 1, 0))
                let targetChapter = matchedByTitle
                    ?? loadedChapters.first(where: { $0.index == clampedIndex })
                    ?? (loadedChapters.indices.contains(clampedIndex) ? loadedChapters[clampedIndex] : loadedChapters.first)
                appState.bookshelfStore.switchSource(
                    bookID: book.id,
                    to: candidate.book,
                    latestChapterTitle: detail.latestChapter ?? loadedChapters.last?.title,
                    intro: detail.intro,
                    totalChapters: loadedChapters.count
                )
                if let targetChapter {
                    appState.bookshelfStore.updateReadingProgress(
                        bookID: book.id,
                        chapterIndex: targetChapter.index,
                        chapterTitle: targetChapter.title,
                        totalChapters: loadedChapters.count
                    )
                }
                chapters = loadedChapters
                selectedChapter = targetChapter
                errorMessage = nil
                showSourceSwitcher = false
                sourceSwitchState = SourceSwitchState()
            case .failure(let error):
                sourceSwitchState = SourceSwitchState(message: "目录加载失败：\(error.displayMessage)")
            }
        case .failure(let error):
            sourceSwitchState = SourceSwitchState(message: "详情加载失败：\(error.displayMessage)")
        }
    }
}

private struct SourceSwitchState: Sendable {
    var isLoading = false
    var candidates: [SourceSwitchCandidate] = []
    var message: String?
    var checkedCount = 0
    var totalCount = 0
}

private struct SourceSwitchCandidate: Identifiable, Sendable {
    var id: String { "\(source.bookSourceUrl)|\(book.bookUrl)" }
    let source: BookSource
    let book: SearchBook
}
