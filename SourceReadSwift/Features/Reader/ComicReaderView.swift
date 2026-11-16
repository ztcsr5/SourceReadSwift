import SwiftUI

enum ComicReadingMode: String, CaseIterable, Identifiable {
    case vertical = "条漫流"
    case horizontalLTR = "左右翻页"
    case horizontalRTL = "日漫翻页"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .vertical: return "arrow.up.and.down.text.horizontal"
        case .horizontalLTR: return "arrow.left.and.right"
        case .horizontalRTL: return "arrow.right.to.line"
        }
    }
}

struct ComicReaderView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nativeReaderSession) private var nativeSession
    @Environment(\.readerNavigationIsTransitioning) private var navigationIsTransitioning
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
    @Environment(\.openURL) private var openURL
    let bookID: String
    let bookTitle: String
    let source: BookSource
    let initialChapterIndex: Int
    let chapters: [BookChapter]
    let engine: SourceEngine
    private let onRequestExit: (() -> Void)?
    let initialPageIndex: Int?
    let initialComicPosition: ComicReadingPosition?
    let onPreviewPosition: ((ReaderPreviewPosition) -> Void)?

    @State private var currentChapterIndex: Int
    @State private var pages: [ComicPage] = []
    @State private var pageRequests: [ComicImageRequest] = []
    @State private var stripWindow = ComicStripChapterWindow()
    @State private var stripLoads: [Int: Task<Void, Never>] = [:]
    @State private var stripFailures: [Int: String] = [:]
    @State private var hasPendingContinuation = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @AppStorage("comic.readingMode") private var readingModeRawValue = ComicReadingMode.vertical.rawValue
    private var readingMode: ComicReadingMode {
        get { ComicReadingMode(rawValue: readingModeRawValue) ?? .vertical }
        nonmutating set { readingModeRawValue = newValue.rawValue }
    }
    @State private var showChrome = false
    @State private var showChapterDrawer = false
    @State private var showsComicSettings = false
    @State private var currentPageIndex: Int = 0
    @State private var scrollTargetIndex: Int?
    @State private var pageDirection = 1
    @State private var pendingChapterIndex: Int?
    @State private var resumeTarget: Int?
    @State private var resumeFraction: Double = 0
    @State private var viewportPosition = ComicViewportPosition()
    @State private var positionSaveTask: Task<Void, Never>?
    @AppStorage("comic_dimming_level") private var dimmingLevel: Double = 0.0
    @AppStorage("reader.showSystemStatusBar") private var showSystemStatusBar = false
    @AppStorage("reader.statusPosition") private var statusPosition = "bottom"
    @AppStorage("comic.continuousStrip") private var isContinuousStrip = true
    @AppStorage("comic.imageQualityReduced") private var reducesImageQuality = false
    @AppStorage("comic.pagePreloadCount") private var preloadPages = ComicDisplayOptions.defaultPrefetchPages
    @AppStorage("comic.canvas") private var canvasRawValue = ComicCanvas.black.rawValue
    @AppStorage("comic.disablesDoubleTap") private var disablesDoubleTap = false
    @AppStorage("comic.disablesQuickActions") private var disablesQuickActions = false
    @AppStorage("comic.reversesTapZones") private var reversesTapZones = false
    @AppStorage("comic.animatesPageTurns") private var animatesPageTurns = true
    @AppStorage("comic.hidesBarsOnSwipe") private var hidesBarsOnSwipe = false
    @AppStorage("comic.stripMargins") private var showsStripMargins = false
    @AppStorage("comic.stripMarginPercent") private var stripMarginPercent = 15
    @AppStorage("comic.stripMarginDirection") private var stripMarginDirection = ComicStripMarginDirection.both.rawValue
    @State private var chapterSearchText = ""
    /// Guards against a slow chapter response overwriting the pages of a
    /// chapter the user opened afterwards.
    @State private var chapterTask: Task<Void, Never>?
    @State private var timeoutTask: Task<Void, Never>?
    @State private var loadGeneration = 0
    @State private var resourceRevision = 0
    @State private var isChapterListReversed = false

    private var prefetchIdentity: String {
        "\(currentChapterIndex)|\(currentPageIndex)|\(pages.count)|\(pageDirection)|\(resourceRevision)|\(readingMode.rawValue)|\(preloadPages)|\(reducesImageQuality)"
    }

    private var displayOptions: ComicDisplayOptions {
        ComicDisplayOptions(canvas: ComicCanvas(rawValue: canvasRawValue) ?? .black, preloadPages: preloadPages,
            reducesImageQuality: reducesImageQuality, disablesDoubleTap: disablesDoubleTap, showsStripMargins: showsStripMargins,
            stripMarginPercent: stripMarginPercent, stripMarginDirection: ComicStripMarginDirection(rawValue: stripMarginDirection) ?? .both)
    }

    private var chapterPrefetchAnchor: Int? {
        guard source.bookSourceUrl != "local://comic", !hasPendingContinuation,
              !pages.isEmpty, !isLoading, pendingChapterIndex == nil else { return nil }
        return currentChapterIndex
    }

    private var filteredChapterIndices: [Int] {
        let indices = Array(chapters.indices)
        let ordered = isChapterListReversed ? Array(indices.reversed()) : indices
        guard !chapterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ordered
        }
        let query = chapterSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ordered.filter { idx in
            let chapter = chapters[idx]
            return chapter.title.lowercased().contains(query) || "\(idx + 1)".contains(query)
        }
    }

    init(
        bookID: String,
        bookTitle: String,
        source: BookSource,
        initialChapterIndex: Int,
        chapters: [BookChapter],
        engine: SourceEngine,
        initialPageIndex: Int? = nil,
        initialComicPosition: ComicReadingPosition? = nil,
        onPreviewPosition: ((ReaderPreviewPosition) -> Void)? = nil,
        onRequestExit: (() -> Void)? = nil
    ) {
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.source = source
        self.initialChapterIndex = initialChapterIndex
        self.chapters = chapters
        self.engine = engine
        self.initialPageIndex = initialPageIndex
        self.initialComicPosition = initialComicPosition
        self.onPreviewPosition = onPreviewPosition
        self.onRequestExit = onRequestExit
        self._currentChapterIndex = State(initialValue: ComicPagePositionPolicy.chapterOffset(initialChapterIndex, in: chapters))
    }

    var currentChapter: BookChapter? {
        guard chapters.indices.contains(currentChapterIndex) else { return nil }
        return chapters[currentChapterIndex]
    }

    var body: some View {
        ZStack {
            Color(uiColor: displayOptions.canvas.color).ignoresSafeArea()

            if isLoading && pages.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(Color(uiColor: displayOptions.canvas.ink))
                        .controlSize(.large)
                    Text("正在加载漫画...")
                        .font(.subheadline)
                        .foregroundStyle(Color(uiColor: displayOptions.canvas.ink).opacity(0.8))
                    Button("返回", action: requestExit).frame(minHeight: 44)
                }
            } else if let error = errorMessage, pages.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: displayOptions.canvas.ink))
                    Button("重试") {
                        loadChapter(at: pendingChapterIndex ?? currentChapterIndex, ignoresCache: true)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("返回", action: requestExit).frame(minHeight: 44)
                }
                .padding()
            } else {
                mainContentView
            }
            if !pages.isEmpty, let errorMessage {
                VStack {
                    HStack {
                        Text(errorMessage).font(.caption).lineLimit(2)
                        Spacer()
                        Button("重试") { loadChapter(at: pendingChapterIndex ?? currentChapterIndex, ignoresCache: true) }
                            .frame(minHeight: 44)
                        Button { self.errorMessage = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }
                            .accessibilityLabel("关闭错误提示")
                    }
                    .padding(.horizontal, 16)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    Spacer()
                }.padding(16).zIndex(3)
            }
            if dimmingLevel > 0 {
                Color.black.opacity(dimmingLevel)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if showChrome {
                chromeOverlay.opacity(navigationIsTransitioning ? 0 : 1)
            } else if !pages.isEmpty {
                VStack {
                    if statusPosition == "top" || statusPosition == "both" {
                        comicHeader
                    }
                    Spacer()
                    if statusPosition == "bottom" || statusPosition == "both" {
                        HStack {
                            Spacer()
                            Text("\(currentPageIndex + 1) / \(pages.count) P")
                                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(ComicChromeSurface(shape: Capsule()))
                                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
                                .padding(.trailing, 16)
                                .padding(.bottom, 20)
                        }
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .task {
            if pages.isEmpty, !isLoading { loadChapter(at: currentChapterIndex, restoresPosition: true) }
        }
        .task(id: prefetchIdentity) { await prefetchVisibleNeighbours() }
        .task(id: chapterPrefetchAnchor, priority: .utility) {
            if let index = chapterPrefetchAnchor { await prefetchChapterResources(around: index) }
        }
        .onChange(of: scenePhase) { if $0 != .active { flushComicPosition() } }
        .onChange(of: currentPageIndex) { page in
            if readingMode != .vertical { viewportPosition.anchor = ComicPageAnchor(pageIndex: page, fraction: 0) }
            scheduleComicPositionSave()
        }
        .onChange(of: readingMode) { mode in
            if mode == .vertical {
                resumeFraction = viewportPosition.anchor.pageIndex == currentPageIndex ? viewportPosition.anchor.fraction : 0
                resumeTarget = currentPageIndex
            } else {
                cancelStripLoads()
                stripWindow.prune(around: currentChapterIndex, includesNeighbours: false)
            }
            scheduleComicPositionSave()
        }
        .sheet(isPresented: $showChapterDrawer) {
            chapterDrawerSheet
        }
        .sheet(isPresented: $showsComicSettings) {
            comicSettingsSheet
        }
        .onChange(of: isContinuousStrip) { isEnabled in
            if !isEnabled {
                cancelStripLoads()
                stripWindow.prune(around: currentChapterIndex, includesNeighbours: false)
            }
        }
        .statusBarHidden(!showChrome && !showSystemStatusBar)
        .readerOpeningContentReady(!pages.isEmpty || errorMessage != nil)
        .toolbar(.hidden, for: .navigationBar)
        .hideRootTabBar()
        .background(ReaderNativeLifecycleBridge(session: nativeSession,
            allowsReturn: !showsComicSettings && !showChapterDrawer, onExit: finishReader,
            onSelectChapter: { index in
                if let offset = chapters.firstIndex(where: { $0.index == index }) { loadChapter(at: offset) }
            }))
        .onDisappear {
            guard !showsComicSettings, !showChapterDrawer, nativeSession == nil else { return }
            finishReader()
        }
    }

    private func finishReader() {
        flushComicPosition()
        loadGeneration &+= 1
        chapterTask?.cancel()
        timeoutTask?.cancel()
        cancelStripLoads()
    }

    private func requestExit() {
        flushComicPosition()
        if let onRequestExit { onRequestExit() } else { dismiss() }
    }

    // MARK: - Main Content Views

    @ViewBuilder
    private var mainContentView: some View {
        switch readingMode {
        case .vertical:
            verticalScrollView.ignoresSafeArea()
        case .horizontalLTR:
            horizontalPager(rtl: false)
        case .horizontalRTL:
            horizontalPager(rtl: true)
        }
    }

    private var verticalScrollView: some View {
        GeometryReader { viewport in
            ComicStripReaderView(
                snapshot: stripWindow.snapshot,
                contentKey: resourceRevision,
                viewport: viewport.size,
                chapterOffset: currentChapterIndex,
                targetPage: resumeTarget ?? scrollTargetIndex,
                targetFraction: resumeTarget == nil ? 0 : resumeFraction,
                footer: stripFooter,
                display: displayOptions,
                reducesMotion: reducesMotion,
                isContinuous: isContinuousStrip,
                onTargetApplied: { resumeTarget = nil; scrollTargetIndex = nil },
                onTap: toggleComicChrome,
                onRefreshAddresses: { loadChapter(at: $0, ignoresCache: true) },
                onPosition: updateStripPosition,
                onApproachChapter: prefetchStripNeighbour,
                onBeginDragging: hideChromeIfRequested
            )
        }
    }

    private var stripFooter: ComicStripReaderView.Footer {
        let last = stripWindow.lastOffset ?? currentChapterIndex
        let next = last + 1
        if isLoading || stripLoads[next] != nil { return .init(title: "正在加载漫画…", isEnabled: false, action: {}) }
        if stripWindow.needsMorePages {
            return .init(title: "重试加载本话剩余图片", isEnabled: true) { loadChapter(at: last, ignoresCache: true) }
        }
        guard chapters.indices.contains(next) else { return .init(title: "已读到目录末尾", isEnabled: false, action: {}) }
        let title = stripFailures[next].map { "下一话加载失败 · 点按重试\n\($0)" } ?? "下一话：\(chapters[next].title)"
        return .init(title: title, isEnabled: true) { loadChapter(at: next) }
    }

    private func horizontalPager(rtl: Bool) -> some View {
        let requests = pageRequests
        let indices = rtl ? Array(requests.indices.reversed()) : Array(requests.indices)
        return TabView(selection: $currentPageIndex) {
            ForEach(indices, id: \.self) { index in
                ComicPageImageView(
                    request: requests[index],
                    pageNumber: index + 1,
                    totalPages: requests.count,
                    revision: resourceRevision,
                    display: displayOptions,
                    onTap: { fraction in handlePageTap(fraction, rtl: rtl) },
                    onRefreshAddresses: refreshCurrentChapterAddresses
                )
                .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .onChange(of: currentPageIndex) { _ in hideChromeIfRequested() }
        .accessibilityIdentifier("comic.pageSurface")
        .accessibilityValue("\(currentChapter?.title ?? "")，第 \(currentPageIndex + 1) 页，共 \(pages.count) 页")
    }

    private func toggleComicChrome() {
        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.16)) { showChrome.toggle() }
    }

    private func hideChromeIfRequested() {
        guard showChrome, hidesBarsOnSwipe else { return }
        toggleComicChrome()
    }

    private func handlePageTap(_ fraction: CGFloat, rtl: Bool) {
        guard !disablesQuickActions else { toggleComicChrome(); return }
        let step = ComicPagePositionPolicy.tapStep(fraction, rtl: rtl != reversesTapZones)
        guard step != 0 else { toggleComicChrome(); return }
        let target = currentPageIndex + step
        if pages.indices.contains(target) {
            pageDirection = step
            withAnimation(reducesMotion || !animatesPageTurns ? nil : .easeInOut(duration: 0.16)) { currentPageIndex = target }
        } else if step > 0, hasPendingContinuation {
            refreshCurrentChapterAddresses()
        } else if step > 0, chapters.indices.contains(currentChapterIndex + 1) {
            loadChapter(at: currentChapterIndex + 1)
        } else if step < 0, chapters.indices.contains(currentChapterIndex - 1) {
            loadChapter(at: currentChapterIndex - 1, startsAtEnd: true)
        }
    }

    // MARK: - Chrome Overlay

    private var chromeOverlay: some View {
        ComicReaderChrome(chapterTitle: currentChapter?.title ?? bookTitle,
            page: .init(index: currentPageIndex, count: pages.count, isRightToLeft: readingMode == .horizontalRTL),
            actions: .init(close: requestExit, showDirectory: { showChapterDrawer = true },
                showSettings: { showsComicSettings = true }, openChapterWebsite: openChapterWebsite,
                selectPage: selectPage))
    }

    private var openChapterWebsite: (() -> Void)? {
        guard let address = currentChapter?.url, let components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.host != nil, components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return { openURL(url) }
    }

    private func selectPage(_ index: Int) {
        guard pages.indices.contains(index), currentPageIndex != index else { return }
        pageDirection = index > currentPageIndex ? 1 : -1
        viewportPosition.anchor = ComicPageAnchor(pageIndex: index, fraction: 0)
        currentPageIndex = index
        if readingMode == .vertical { scrollTargetIndex = index }
    }

    private var comicSettingsSheet: some View {
        ComicReaderSettingsView(preferences: .init(
            mode: Binding(get: { readingMode }, set: { readingMode = $0 }),
            continuous: $isContinuousStrip, reducedQuality: $reducesImageQuality,
            disablesDoubleTap: $disablesDoubleTap, hidesBars: $hidesBarsOnSwipe, canvas: $canvasRawValue,
            brightness: Binding(get: { 1 - dimmingLevel }, set: { dimmingLevel = min(max(1 - $0, 0), 0.8) }),
            systemStatus: $showSystemStatusBar, pageStatus: $statusPosition,
            disablesQuickActions: $disablesQuickActions, reverseTapZones: $reversesTapZones, transitions: $animatesPageTurns,
            preloadPages: $preloadPages, stripMargins: $showsStripMargins, marginPercent: $stripMarginPercent,
            marginDirection: $stripMarginDirection
        ), chapter: comicSettingsChapterActions)
    }

    private var comicSettingsChapterActions: ComicReaderSettingsView.ChapterActions {
        let index = currentChapterIndex
        let previous: (() -> Void)? = chapters.indices.contains(index - 1) ? { loadChapter(at: index - 1, startsAtEnd: true) } : nil
        let next: (() -> Void)? = chapters.indices.contains(index + 1) ? { loadChapter(at: index + 1) } : nil
        let isDownloading = appState.chapterDownloadCoordinator.isRunning(bookID: bookID)
        let download: (() -> Void)?
        if let currentChapter, source.bookSourceUrl != "local://comic", !ComicOfflineArchive.isOfflineChapter(currentChapter) {
            download = {
                if isDownloading { appState.chapterDownloadCoordinator.cancel(bookID: bookID) }
                else { downloadCurrentChapter(currentChapter) }
            }
        } else {
            download = nil
        }
        return .init(previous: previous, next: next, download: download, isDownloading: isDownloading)
    }

    private var chapterDrawerSheet: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    ForEach(filteredChapterIndices, id: \.self) { idx in
                        comicDirectoryRow(idx).id(idx)
                    }
                }
                .onAppear {
                    DispatchQueue.main.async { proxy.scrollTo(currentChapterIndex, anchor: .center) }
                }
                .onChange(of: isChapterListReversed) { _ in
                    guard chapterSearchText.isEmpty else { return }
                    DispatchQueue.main.async { proxy.scrollTo(currentChapterIndex, anchor: .center) }
                }
            }
            .searchable(text: $chapterSearchText, prompt: "搜索话数或标题")
            .navigationTitle("漫画目录 (\(chapters.count) 话)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        isChapterListReversed.toggle()
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isChapterListReversed ? Color.accentColor : .secondary)
                    }
                    .accessibilityLabel("正序倒序切换")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showChapterDrawer = false
                    }
                }
            }
        }
    }

    private func comicDirectoryRow(_ index: Int) -> some View {
        Button {
            loadChapter(at: index)
            showChapterDrawer = false
        } label: {
            HStack {
                Text("\(index + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .leading)
                Text(chapters[index].title)
                    .foregroundStyle(index == currentChapterIndex ? Color.accentColor : .primary)
                    .lineLimit(1)
                Spacer()
                if index == currentChapterIndex {
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                }
            }
        }
        .accessibilityAddTraits(index == currentChapterIndex ? .isSelected : [])
    }

    // MARK: - Logic

    private func downloadCurrentChapter(_ chapter: BookChapter) {
        appState.chapterDownloadCoordinator.start(bookID: bookID, source: source, title: bookTitle, chapters: [chapter],
            engine: engine, cacheStore: appState.chapterContentCacheStore, purifyRules: appState.purifyRuleStore.enabledPatterns)
    }

    private var resourceLoader: ComicChapterResourceLoader {
        ComicChapterResourceLoader(source: source, engine: engine,
            store: appState.chapterContentCacheStore, archive: appState.comicOfflineArchive)
    }

    private func cancelStripLoads() {
        for task in stripLoads.values { task.cancel() }
        stripLoads.removeAll()
        stripFailures.removeAll()
    }

    private func prefetchStripNeighbour(_ index: Int) {
        guard readingMode == .vertical, isContinuousStrip, !isLoading,
              chapters.indices.contains(index), abs(index - currentChapterIndex) == 1,
              stripWindow.chapter(at: index) == nil, stripLoads[index] == nil, stripFailures[index] == nil,
              !(index == (stripWindow.lastOffset ?? currentChapterIndex) + 1 && stripWindow.needsMorePages) else { return }
        let generation = loadGeneration
        let chapter = chapters[index]
        let rules = appState.purifyRuleStore.enabledPatterns
        let loader = resourceLoader
        stripLoads[index] = Task { @MainActor in
            let outcome = await loader.load(chapter, rules: rules, forcesRefresh: false, isSpeculative: true)
            guard !Task.isCancelled, loadGeneration == generation, readingMode == .vertical, isContinuousStrip else { return }
            stripLoads.removeValue(forKey: index)
            guard let resources = outcome.resources, resources.canReuseFromCache else {
                stripFailures[index] = outcome.error ?? "本话尚未拿到完整的图片地址。"
                return
            }
            stripWindow.stitch(makeStripChapter(resources, index: index), around: currentChapterIndex)
        }
    }

    private func updateStripPosition(_ key: ComicStripPageKey, _ anchor: ComicPageAnchor, _ isSettled: Bool) {
        // UIKit reports its old origin when installing a requested resume or directory target.
        guard resumeTarget == nil, scrollTargetIndex == nil, !isLoading,
              let chapter = stripWindow.chapter(at: key.chapterOffset) else { return }
        let chapterChanged = currentChapterIndex != key.chapterOffset
        let pageChanged = currentPageIndex != anchor.pageIndex
        if chapterChanged {
            pageDirection = key.chapterOffset > currentChapterIndex ? 1 : -1
            currentChapterIndex = key.chapterOffset
            pages = chapter.resources.pages
            pageRequests = chapter.requests
            hasPendingContinuation = chapter.resources.hasPendingContinuation
        } else if pageChanged {
            pageDirection = anchor.pageIndex > currentPageIndex ? 1 : -1
        }
        viewportPosition.anchor = anchor
        if pageChanged { currentPageIndex = anchor.pageIndex }
        if isSettled { stripWindow.prune(around: key.chapterOffset, includesNeighbours: isContinuousStrip) }
        if isSettled || chapterChanged { scheduleComicPositionSave() }
    }

    private func refreshCurrentChapterAddresses() {
        guard !isLoading else { return }
        loadChapter(at: currentChapterIndex, ignoresCache: true)
    }

    private func loadChapter(at index: Int, restoresPosition: Bool = false, startsAtEnd: Bool = false, ignoresCache: Bool = false) {
        guard chapters.indices.contains(index) else {
            isLoading = false
            errorMessage = "漫画目录为空，请返回书籍详情刷新目录"
            return
        }
        chapterTask?.cancel()
        timeoutTask?.cancel()
        cancelStripLoads()
        let chapter = chapters[index]
        pendingChapterIndex = index
        isLoading = true
        errorMessage = nil
        scrollTargetIndex = nil
        loadGeneration &+= 1
        let generation = loadGeneration
        let shelf = appState.bookshelfStore.book(id: bookID)
        let shouldResume = restoresPosition || (ignoresCache && pages.isEmpty)
        let restoredPage = shelf?.currentChapterIndex == chapter.index ? shelf?.currentParagraphIndex :
            (chapter.index == initialChapterIndex ? initialPageIndex : nil)
        let savedPage = shouldResume ? restoredPage ?? 0 : 0
        let rules = appState.purifyRuleStore.enabledPatterns
        let loader = resourceLoader

        timeoutTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard generation == loadGeneration, isLoading else { return }
            loadGeneration &+= 1
            chapterTask?.cancel()
            isLoading = false
            errorMessage = "漫画章节请求超过 30 秒，可重试或返回换源"
        }
        chapterTask = Task { @MainActor in
            let outcome = await loader.load(chapter, rules: rules, forcesRefresh: ignoresCache, isSpeculative: false)
            guard !Task.isCancelled, generation == loadGeneration else { return }
            timeoutTask?.cancel()
            isLoading = false
            if let resources = outcome.resources, !resources.pages.isEmpty, outcome.error == nil || pages.isEmpty {
                let target = ignoresCache && index == currentChapterIndex && !pages.isEmpty ? currentPageIndex : savedPage
                let restores = shouldResume || (ignoresCache && index == currentChapterIndex)
                let anchor = resolveChapterAnchor(resources, at: index, fallbackPage: target, restoresPosition: restores)
                showChapter(resources, index: index, savedAnchor: anchor, startsAtEnd: startsAtEnd)
            }
            if let error = outcome.error { errorMessage = error }
        }
    }

    private func resolveChapterAnchor(_ resources: ComicChapterResources, at index: Int, fallbackPage: Int,
                                      restoresPosition: Bool) -> ComicPageAnchor {
        guard restoresPosition else { return ComicPageAnchor(pageIndex: fallbackPage, fraction: 0) }
        let chapter = chapters[index]
        let cursor: ComicReadingPosition?
        if index == currentChapterIndex, !pages.isEmpty {
            cursor = ComicReadingPosition(sourceURL: source.bookSourceUrl, chapter: chapter,
                                          pages: pages, anchor: viewportPosition.anchor)
        } else {
            cursor = appState.bookshelfStore.book(id: bookID)?.comicPosition ?? initialComicPosition
        }
        return cursor?.resolve(sourceURL: source.bookSourceUrl, chapter: chapter, pages: resources.pages)
            ?? ComicPageAnchor(pageIndex: fallbackPage, fraction: 0)
    }

    private func showChapter(_ resources: ComicChapterResources, index: Int, savedAnchor: ComicPageAnchor, startsAtEnd: Bool) {
        let page = ComicPagePositionPolicy.start(savedPage: savedAnchor.pageIndex, count: resources.pages.count, startsAtEnd: startsAtEnd)
        let chapter = makeStripChapter(resources, index: index)
        resourceRevision &+= 1
        currentChapterIndex = index
        pendingChapterIndex = nil
        pages = resources.pages
        pageRequests = chapter.requests
        stripWindow.reset(to: chapter)
        hasPendingContinuation = resources.hasPendingContinuation
        currentPageIndex = page
        viewportPosition.anchor = ComicPageAnchor(pageIndex: page, fraction: startsAtEnd ? 0 : savedAnchor.fraction)
        if readingMode == .vertical {
            resumeFraction = viewportPosition.anchor.fraction
            resumeTarget = page
        }
        errorMessage = resources.hasPendingContinuation ? "本话仅加载了部分图片，可重试剩余内容。" : nil
        persistComicPosition()
    }

    private func persistComicPosition() {
        guard !pages.isEmpty, pages.indices.contains(currentPageIndex), let chapter = currentChapter else { return }
        let anchor = viewportPosition.anchor.pageIndex == currentPageIndex ? viewportPosition.anchor
            : ComicPageAnchor(pageIndex: currentPageIndex, fraction: 0)
        let cursor = ComicReadingPosition(sourceURL: source.bookSourceUrl, chapter: chapter, pages: pages, anchor: anchor)
        guard let book = appState.bookshelfStore.book(id: bookID) else {
            onPreviewPosition?(ReaderPreviewPosition(bookID: bookID, chapterIndex: chapter.index,
                chapterTitle: chapter.title, paragraphIndex: currentPageIndex, comicPosition: cursor))
            return
        }
        guard book.currentChapterIndex != chapter.index || book.currentParagraphIndex != currentPageIndex || book.comicPosition != cursor else { return }
        let knownChapterCount = max(chapters.count, (chapters.last?.index ?? 0) + 1)
        appState.bookshelfStore.updateReadingProgress(bookID: bookID, chapterIndex: chapter.index,
            chapterTitle: chapter.title, totalChapters: knownChapterCount, paragraphIndex: currentPageIndex, comicPosition: cursor)
    }

    private func scheduleComicPositionSave() {
        positionSaveTask?.cancel()
        positionSaveTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            persistComicPosition()
        }
    }

    private func flushComicPosition() {
        positionSaveTask?.cancel()
        positionSaveTask = nil
        appState.finishReadingWritesInBackground { persistComicPosition() }
    }

    private func prefetchVisibleNeighbours() async {
        guard readingMode != .vertical else { return }
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled, ProcessInfo.processInfo.thermalState.rawValue < 2 else { return }
        let indices = ComicPagePositionPolicy.prefetchOrder(around: currentPageIndex, count: pageRequests.count,
            direction: pageDirection, depth: preloadPages)
        let requests = indices.map { pageRequests[$0] }
        let maxPixels = displayOptions.maxImagePixels
        for request in requests {
            guard !Task.isCancelled else { return }
            guard let url = URL(string: request.url) else { continue }
            _ = await RemoteImageLoader.shared.comicPage(for: url, headers: request.headers, maxPixelSize: maxPixels,
                                                        decodeContext: request.decodeContext)
        }
    }

    /// Cache page addresses for the candidate window; decoded images remain viewport-bound.
    private func prefetchChapterResources(around cursor: Int) async {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState.rawValue < 2 else { return }
        let candidates = ReaderChapterWindowPolicy.prefetchOrder(
            current: cursor, radius: ReaderPreloadPolicy.defaultCount, lowerBound: 0, upperBound: chapters.count, loaded: []
        )
        let rules = appState.purifyRuleStore.enabledPatterns
        for index in candidates {
            guard !Task.isCancelled, chapterPrefetchAnchor == cursor else { return }
            // The mounted strip owns immediate neighbours so they cannot race
            // a distant address-prefetch request for the same chapter.
            if readingMode == .vertical, isContinuousStrip, abs(index - cursor) == 1 { continue }
            await prefetchChapterResources(chapters[index], around: cursor, purifyRules: rules)
            await Task.yield()
        }
    }

    private func prefetchChapterResources(_ chapter: BookChapter, around cursor: Int, purifyRules: [String]) async {
        guard !ComicOfflineArchive.isOfflineChapter(chapter),
              !appState.chapterContentCacheStore.isCached(sourceURL: source.bookSourceUrl, chapter: chapter, purifyRules: purifyRules),
              !(await appState.comicOfflineArchive.hasManifest(sourceURL: source.bookSourceUrl, chapter: chapter)),
              !Task.isCancelled, chapterPrefetchAnchor == cursor else { return }
        let result = await ReaderChapterPrefetchBudget.fetch(using: engine, source: source, chapter: chapter)
        guard case .success(let loaded)? = result,
              !Task.isCancelled, chapterPrefetchAnchor == cursor else { return }
        let isComplete = await Task.detached(priority: .utility) { ComicChapterResources(content: loaded).canReuseFromCache }.value
        guard isComplete, !Task.isCancelled, chapterPrefetchAnchor == cursor else { return }
        appState.chapterContentCacheStore.save(loaded, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
    }

    private func makeStripChapter(_ resources: ComicChapterResources, index: Int) -> ComicStripChapter {
        let chapterURL = chapters[index].url
        let headers = SourceRequestBuilder().imageRequestHeaders(for: source, chapterURL: chapterURL)
        let decodeContext = SourceImageDecodeContext.resolve(source: source, chapter: chapters[index], engine: engine)
        let requests = resources.pages.map { page in
            let request = ComicImageRequest(url: page.url, headers: page.headers)
            if URL(string: page.url)?.isFileURL == true { return ComicImageRequest(url: page.url, headers: [:]) }
            return ComicImageRequest(url: page.url, headers: request.mergingHeaders(headers, chapterURL: chapterURL),
                                     decodeContext: decodeContext)
        }
        return ComicStripChapter(offset: index, resources: resources, requests: requests)
    }

    private var comicHeader: some View {
        HStack(spacing: 12) {
            Text(currentChapter?.title ?? bookTitle)
                .lineLimit(1)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))

            Spacer(minLength: 8)

            ReaderMinuteClockText()
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(ComicChromeSurface(shape: Capsule()))
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.8))
        .padding(.top, 12)
    }
}

// MARK: - Comic Page Image with Pinch-to-Zoom

private struct ComicPageImageView: View {
    let request: ComicImageRequest
    let pageNumber: Int
    let totalPages: Int
    let revision: Int
    let display: ComicDisplayOptions
    let onTap: (CGFloat) -> Void
    let onRefreshAddresses: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    @State private var loaded: (key: LoadKey, image: UIImage)?
    @State private var failure: ComicImageFailure?
    @State private var attempt = 0

    private struct LoadKey: Equatable {
        let request: ComicImageRequest
        let attempt: Int
        let revision: Int
        let maxPixels: CGFloat
    }

    private var image: UIImage? {
        if let loaded, loaded.key.request == request, loaded.key.revision == revision,
           loaded.key.maxPixels == display.maxImagePixels { return loaded.image }
        guard let address = URL(string: request.url) else { return nil }
        return RemoteImageLoader.shared.cachedComicPage(for: address, headers: request.headers, maxPixelSize: display.maxImagePixels,
                                                        decodeContext: request.decodeContext)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            if let failure {
                Image(systemName: "photo.badge.exclamationmark").font(.title2)
                Text("第 \(pageNumber) 页加载失败").font(.subheadline)
                Text(failure.message).font(.caption).opacity(0.7)
                Button("重新加载这一页") { attempt += 1 }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                if failure.canRefreshAddress {
                    Button("重新获取图片地址", action: onRefreshAddresses)
                        .frame(minHeight: 44)
                }
            } else {
                ProgressView().tint(Color(uiColor: display.canvas.ink))
                Text("正在加载第 \(pageNumber) / \(totalPages) 页").font(.caption)
            }
        }
        .foregroundStyle(Color(uiColor: display.canvas.ink))
        .frame(maxWidth: .infinity, minHeight: 320)
    }

    var body: some View {
        ZStack {
            if let image {
                ComicPageZoomView(image: image, reducesMotion: reducesMotion, onFitTap: onTap,
                    canvas: display.canvas, disablesDoubleTap: display.disablesDoubleTap)
            } else {
                placeholder.onTapGesture { onTap(0.5) }
            }
        }
        .task(id: LoadKey(request: request, attempt: attempt, revision: revision, maxPixels: display.maxImagePixels)) {
            failure = nil
            let key = LoadKey(request: request, attempt: attempt, revision: revision, maxPixels: display.maxImagePixels)
            guard let imageURL = URL(string: key.request.url) else { failure = .invalidResponse; return }
            let result = await RemoteImageLoader.shared.comicPage(for: imageURL, headers: key.request.headers, maxPixelSize: key.maxPixels,
                                                                 decodeContext: key.request.decodeContext)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let image): loaded = (key, image)
            case .failure(let error): failure = error
            }
        }
    }
}

enum ComicPagePositionPolicy {
    // The budget bounds decoded textures; long strips still use their aspect ratio.
    static let maxImagePixels: CGFloat = 4096

    static func chapterOffset(_ index: Int, in chapters: [BookChapter]) -> Int {
        chapters.firstIndex(where: { $0.index == index }) ?? min(max(index, 0), max(chapters.count - 1, 0))
    }

    static func start(savedPage: Int, count: Int, startsAtEnd: Bool) -> Int {
        let last = max(count - 1, 0)
        return startsAtEnd ? last : min(max(savedPage, 0), last)
    }

    static func neighbours(of page: Int, count: Int, direction: Int) -> [Int] {
        let step = direction < 0 ? -1 : 1
        return [page + step, page + 2 * step, page - step].filter { (0..<max(count, 0)).contains($0) }
    }

    /// Favors the direction of travel and bounds speculative subscribers independently of chapter size.
    static func prefetchOrder(around page: Int, count: Int, direction: Int, depth: Int) -> [Int] {
        let depth = min(max(depth, 0), ComicDisplayOptions.maximumPrefetchPages)
        guard depth > 0, (0..<max(count, 0)).contains(page) else { return [] }
        let step = direction < 0 ? -1 : 1
        let forward = (1...depth).map { page + $0 * step }
        let candidates = depth > 1 ? forward + [page - step] : forward
        return candidates.filter { (0..<count).contains($0) }
    }

    static func tapStep(_ fraction: CGFloat, rtl: Bool) -> Int {
        if fraction < 0.26 { return rtl ? 1 : -1 }
        if fraction > 0.74 { return rtl ? -1 : 1 }
        return 0
    }

    static func page(at line: CGFloat, frames: [Int: CGRect]) -> Int? {
        let ordered = frames.filter { $0.value.height > 0 && $0.value.maxY > line }
        return ordered.min { lhs, rhs in
            lhs.value.minY == rhs.value.minY ? lhs.key < rhs.key : lhs.value.minY < rhs.value.minY
        }?.key
    }
}
