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
    @State private var sourceSwitchGeneration = UUID()
    @State private var sourceSwitchApplyTask: Task<Void, Never>?
    @State private var isApplyingSource = false
    @State private var switchRefreshRequested = false
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
        .background(ReaderTabChromeExitBridge(owner: gatewayTabChromeOwner))
        .toolbar(.hidden, for: .tabBar)
        .environment(\.readerTemporaryCoverPresented, showSourceSwitcher)
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
        .fullScreenCover(isPresented: $showSourceSwitcher) {
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
                    onRequestSourceSwitch: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showSourceSwitcher = true
                    },
                    onRequestBookDetail: {
                        showBookDetailSheet = true
                    }
                )
                .id("remote-reader|\(currentBook.sourceURL)|\(currentBook.bookURL)")
            )
        } else if let errorMessage {
            return AnyView(readerRecoveryErrorView(errorMessage))
        } else {
            return AnyView(
                ReaderOpeningPage(book: currentBook)
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
            let target = cached.chapters.first(where: { $0.index == targetIndex })
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
            let target = cached.first(where: { $0.index == targetIndex })
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
            // 首次从头开书先取目录头部；恢复非首章必须抓到真实目标，不能回退第一章。
            // 分页目录是串行抓取，30 页会让「进书」停在加载页上。
            let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
            let pages = targetIndex > 0 ? 30 : 8
            let chapterResult = await AsyncTimeout.run(seconds: 20) {
                await engine.getChapterList(source: source, book: loadedDetail, maxPages: pages)
            } ?? .failure(.network("Chapter list timed out"))
            switch chapterResult {
            case .success(let loadedChapters):
                chapters = loadedChapters
                appState.bookTOCacheStore.save(
                    detail: loadedDetail,
                    chapters: loadedChapters,
                    sourceURL: source.bookSourceUrl,
                    bookURL: activeBook.bookURL,
                    isComplete: pages == 30
                )
                let target = loadedChapters.first(where: { $0.index == targetIndex })
                if let target {
                    appState.bookshelfStore.updateDetails(
                        bookID: activeBook.id,
                        latestChapterTitle: loadedDetail.latestChapter,
                        intro: loadedDetail.intro,
                        totalChapters: loadedChapters.count,
                        coverURL: loadedDetail.coverUrl
                    )
                    selectedChapter = target
                    // 阅读器已经打开，目录更新交给后台，不阻塞目标正文。
                    refreshBookDetailAndTOC(source: source, book: activeBook)
                } else {
                    errorMessage = loadedChapters.isEmpty ? "目录为空" : "目录尚未包含上次阅读的章节，请刷新目录后重试；原阅读进度已保留"
                }
            case .failure(let error):
                let cached = appState.chapterContentCacheStore.cachedChapters(
                    sourceURL: source.bookSourceUrl,
                    bookURL: activeBook.bookURL
                )
                let targetIndex = requestedChapterIndex ?? activeBook.currentChapterIndex
                if let target = cached.first(where: { $0.index == targetIndex }) {
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
            if let target = cached.first(where: { $0.index == targetIndex }) {
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
                guard currentBook.sourceURL == activeBook.sourceURL,
                      currentBook.bookURL == activeBook.bookURL else { return }
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

                if isApplyingSource {
                    ProgressView("正在对齐阅读章节…").padding(.horizontal)
                }
                if let message = sourceSwitchState.message, !sourceSwitchState.candidates.isEmpty {
                    Text(message).font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                if sourceSwitchState.isLoading, sourceSwitchState.candidates.isEmpty {
                    ProgressView(sourceSwitchProgressTitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = sourceSwitchState.message, sourceSwitchState.candidates.isEmpty {
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
                                sourceSwitchGeneration = UUID()
                                sourceSwitchSearchTrigger &+= 1
                                isApplyingSource = true
                                sourceSwitchState.isLoading = false
                                sourceSwitchApplyTask?.cancel()
                                sourceSwitchApplyTask = Task { await applySwitch(candidate) }
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(candidate.book.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(candidate.source.bookSourceName) · \(candidate.book.author ?? "作者未知")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(candidate.chapterCount.map { "目录 \($0) 章" } ?? "章节数待统计")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.secondary)
                                    Text(candidate.book.bookUrl)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                }
                            }
                            .disabled(isApplyingSource)
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
                    Button("刷新") {
                        switchRefreshRequested = true
                        sourceSwitchGeneration = UUID()
                        sourceSwitchState.message = nil
                        sourceSwitchSearchTrigger &+= 1
                    }
                    .disabled(isApplyingSource || sourceSwitchState.isLoading)
                }
            }
            .task(id: sourceSwitchSearchTrigger) {
                guard !isApplyingSource else { return }
                await searchSwitchCandidates(force: switchRefreshRequested)
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

    private var sourceSwitchProgressTitle: String {
        guard sourceSwitchState.totalCount > 0 else { return "正在搜索可用换源" }
        return "正在搜索 \(sourceSwitchState.checkedCount)/\(sourceSwitchState.totalCount)"
    }

    private func persistSwitchCandidates() {
        let active = currentBook
        var cached = sourceSwitchState.candidates.map {
            SourceSwitchCacheStore.Candidate(sourceURL: $0.source.bookSourceUrl,
                sourceName: $0.source.bookSourceName, book: $0.book, chapterCount: $0.chapterCount)
        }
        if !cached.contains(where: { $0.sourceURL == active.sourceURL && $0.book.bookUrl == active.bookURL }) {
            cached.append(SourceSwitchCacheStore.Candidate(sourceURL: active.sourceURL,
                sourceName: active.sourceName, book: active.asSearchBook,
                chapterCount: appState.bookTOCacheStore.entry(sourceURL: active.sourceURL,
                    bookURL: active.bookURL).flatMap { $0.isComplete == true ? $0.chapters.count : nil }))
        }
        SourceSwitchCacheStore.shared.save(title: active.title, author: active.author,
            candidates: cached)
    }

    private func searchSwitchCandidates(force: Bool = false) async {
        let active = currentBook
        let token = UUID(); sourceSwitchGeneration = token
        switchRefreshRequested = false
        sourceSwitchState.message = nil
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
            if !sourceSwitchState.candidates.isEmpty {
                let missing = sourceSwitchState.candidates.filter { $0.chapterCount == nil }
                await hydrateSwitchCounts(missing, token: token)
                return
            }
        }
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
                    guard !Task.isCancelled, let result, case .success(let books) = result,
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
                    await hydrateSwitchCount(candidate, token: token)
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

    private func hydrateSwitchCounts(_ candidates: [SourceSwitchCandidate], token: UUID) async {
        await withTaskGroup(of: Void.self) { group in
            var iterator = candidates.makeIterator()
            for _ in 0..<min(3, candidates.count) {
                if let candidate = iterator.next() {
                    group.addTask { await hydrateSwitchCount(candidate, token: token) }
                }
            }
            while await group.next() != nil {
                guard !Task.isCancelled, sourceSwitchGeneration == token else { group.cancelAll(); break }
                if let candidate = iterator.next() {
                    group.addTask { await hydrateSwitchCount(candidate, token: token) }
                }
            }
        }
    }

    @MainActor private func hydrateSwitchCount(_ candidate: SourceSwitchCandidate, token: UUID) async {
        guard !Task.isCancelled, sourceSwitchGeneration == token else { return }
        let source = candidate.source, match = candidate.book
        let cached = appState.bookTOCacheStore.entry(sourceURL: source.bookSourceUrl, bookURL: match.bookUrl)
        var count = cached.flatMap { $0.isComplete == true ? $0.chapters.count : nil }
        if count == nil {
            let engine = appState.engine
            let metadata = await AsyncTimeout.run(seconds: 12) {
                guard case .success(let detail) = await engine.getBookDetail(source: source, book: match),
                      case .success(let chapters) = await engine.getChapterList(source: source, book: detail)
                else { return (nil as BookDetail?, [BookChapter]()) }
                return (detail as BookDetail?, chapters)
            }
            guard !Task.isCancelled, sourceSwitchGeneration == token, !isApplyingSource else { return }
            if let metadata, !metadata.1.isEmpty {
                count = metadata.1.count
                appState.bookTOCacheStore.save(detail: metadata.0, chapters: metadata.1,
                    sourceURL: source.bookSourceUrl, bookURL: match.bookUrl)
            }
        }
        guard !Task.isCancelled, sourceSwitchGeneration == token, !isApplyingSource,
              let i = sourceSwitchState.candidates.firstIndex(where: { $0.id == candidate.id }) else { return }
        sourceSwitchState.candidates[i].chapterCount = count
        persistSwitchCandidates()
    }

    private func applySwitch(_ candidate: SourceSwitchCandidate) async {
        let token = sourceSwitchGeneration
        let progress = currentBook
        defer { if sourceSwitchGeneration == token { isApplyingSource = false } }
        persistSwitchCandidates()
        let cached = appState.bookTOCacheStore.entry(sourceURL: candidate.source.bookSourceUrl, bookURL: candidate.book.bookUrl)
        let engine = appState.engine
        let loaded: (BookDetail, [BookChapter])?
        if cached?.isComplete == true, let detail = cached?.detail, let chapters = cached?.chapters, !chapters.isEmpty {
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
        // End the covered reader while its old source/progress are still authoritative.
        NotificationCenter.default.post(name: .readerSourceWillChange, object: book.id)
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
    var chapterCount: Int? = nil
}
