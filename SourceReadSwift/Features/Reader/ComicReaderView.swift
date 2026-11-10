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

    /// Comic CDNs are usually hotlink-protected; every page request reuses the
    /// source's own Referer / User-Agent / Cookie headers. Built once in init
    /// so a long page list does not re-decode the header JSON per row.
    @State private var imageHeaders: [String: String]

    @State private var currentChapterIndex: Int
    @State private var pages: [ComicPage] = []
    @State private var stripRequests: [ComicImageRequest] = []
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
    @State private var currentPageIndex: Int = 0
    @State private var scrollTargetIndex: Int?
    @State private var pageDirection = 1
    @State private var pendingChapterIndex: Int?
    @State private var resumeTarget: Int?
    @State private var resumeFraction: Double = 0
    @State private var viewportPosition = ComicViewportPosition()
    @State private var positionSaveTask: Task<Void, Never>?
    @State private var inspectedPage: ComicInspectedPage?
    @AppStorage("comic_dimming_level") private var dimmingLevel: Double = 0.0
    @AppStorage("reader.showSystemStatusBar") private var showSystemStatusBar = false
    @AppStorage("reader.statusPosition") private var statusPosition = "bottom"
    @State private var chapterSearchText = ""
    /// Guards against a slow chapter response overwriting the pages of a
    /// chapter the user opened afterwards.
    @State private var chapterTask: Task<Void, Never>?
    @State private var timeoutTask: Task<Void, Never>?
    @State private var loadGeneration = 0
    @State private var resourceRevision = 0
    @State private var isChapterListReversed = false

    private var prefetchIdentity: String {
        "\(currentChapterIndex)|\(currentPageIndex)|\(pages.count)|\(pageDirection)|\(resourceRevision)|\(readingMode.rawValue)"
    }

    private var nextChapterPrefetchIndex: Int? {
        guard !hasPendingContinuation, !pages.isEmpty, currentPageIndex >= max(pages.count - 3, 0),
              chapters.indices.contains(currentChapterIndex + 1) else { return nil }
        return currentChapterIndex + 1
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
        _imageHeaders = State(initialValue: SourceRequestBuilder().imageRequestHeaders(for: source))
        self._currentChapterIndex = State(initialValue: ComicPagePositionPolicy.chapterOffset(initialChapterIndex, in: chapters))
    }

    var currentChapter: BookChapter? {
        guard chapters.indices.contains(currentChapterIndex) else { return nil }
        return chapters[currentChapterIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isLoading && pages.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.large)
                    Text("正在加载漫画...")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Button("返回") { dismiss() }.frame(minHeight: 44)
                }
            } else if let error = errorMessage, pages.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Button("重试") {
                        loadChapter(at: pendingChapterIndex ?? currentChapterIndex, ignoresCache: true)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("返回") { dismiss() }.frame(minHeight: 44)
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
        .task(id: nextChapterPrefetchIndex, priority: .utility) {
            if let index = nextChapterPrefetchIndex { await prefetchNextChapter(at: index) }
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
            }
            scheduleComicPositionSave()
        }
        .sheet(isPresented: $showChapterDrawer) {
            chapterDrawerSheet
        }
        .fullScreenCover(item: $inspectedPage) { inspected in
            ComicPageZoomView(image: inspected.image, reducesMotion: reducesMotion)
                .ignoresSafeArea()
                .overlay(alignment: .topTrailing) {
                    Button { inspectedPage = nil } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                            .background(.regularMaterial, in: Circle())
                    }.padding(16).accessibilityLabel("关闭图片")
                }
        }
        .statusBarHidden(!showChrome && !showSystemStatusBar)
        .readerOpeningContentReady(!pages.isEmpty || errorMessage != nil)
        .toolbar(.hidden, for: .navigationBar)
        .hideRootTabBar()
        .background(ReaderNativeLifecycleBridge(session: nativeSession,
            allowsReturn: inspectedPage == nil && !showChapterDrawer, onExit: finishReader))
        .onDisappear {
            guard inspectedPage == nil, nativeSession?.phase != .returning else { return }
            finishReader()
        }
    }

    private func finishReader() {
        flushComicPosition()
        loadGeneration &+= 1
        chapterTask?.cancel()
        timeoutTask?.cancel()
    }

    // MARK: - Main Content Views

    @ViewBuilder
    private var mainContentView: some View {
        switch readingMode {
        case .vertical:
            verticalScrollView
        case .horizontalLTR:
            horizontalPager(rtl: false)
        case .horizontalRTL:
            horizontalPager(rtl: true)
        }
    }

    private var verticalScrollView: some View {
        GeometryReader { viewport in
            ComicStripReaderView(
                requests: stripRequests,
                contentKey: "\(currentChapterIndex)|\(resourceRevision)",
                viewportWidth: viewport.size.width,
                targetPage: resumeTarget ?? scrollTargetIndex,
                footerTitle: stripFooterTitle,
                canActivateFooter: !isLoading && (hasPendingContinuation || chapters.indices.contains(currentChapterIndex + 1)),
                reducesMotion: reducesMotion,
                onVisiblePage: { page in
                    guard resumeTarget == nil, page != currentPageIndex else { return }
                    pageDirection = page > currentPageIndex ? 1 : -1
                    currentPageIndex = page
                },
                onTargetApplied: { resumeTarget = nil; scrollTargetIndex = nil },
                onTap: toggleComicChrome,
                onRefreshAddresses: refreshCurrentChapterAddresses,
                onFooter: {
                    guard !isLoading else { return }
                    if hasPendingContinuation { refreshCurrentChapterAddresses() }
                    else if chapters.indices.contains(currentChapterIndex + 1) {
                        loadChapter(at: currentChapterIndex + 1)
                    }
                },
                targetFraction: resumeTarget == nil ? 0 : resumeFraction,
                onPosition: { anchor, isSettled in
                    // UIKit can report the temporary top before applying the
                    // requested resume anchor. It must not overwrite that cursor.
                    guard resumeTarget == nil else { return }
                    viewportPosition.anchor = anchor
                    if isSettled { scheduleComicPositionSave() }
                }
            )
        }
    }

    private var stripFooterTitle: String {
        if isLoading { return "正在加载漫画…" }
        if hasPendingContinuation { return "重试加载本话剩余图片" }
        if chapters.indices.contains(currentChapterIndex + 1) { return "下一话：\(chapters[currentChapterIndex + 1].title)" }
        return "已读到目录末尾"
    }

    private func horizontalPager(rtl: Bool) -> some View {
        TabView(selection: $currentPageIndex) {
            let displayedPages = rtl ? Array(pages.reversed()) : pages
            ForEach(displayedPages) { page in
                ComicPageImageView(
                    url: page.url,
                    pageNumber: page.id + 1,
                    totalPages: pages.count,
                    headers: pageRequestHeaders(page),
                    resourceRevision: resourceRevision,
                    usesNativeZoom: true,
                    onTap: { fraction in handlePageTap(fraction, rtl: rtl) },
                    onRefreshAddresses: refreshCurrentChapterAddresses
                )
                .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .accessibilityIdentifier("comic.pageSurface")
        .accessibilityValue("\(currentChapter?.title ?? "")，第 \(currentPageIndex + 1) 页，共 \(pages.count) 页")
    }

    private func toggleComicChrome() {
        withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.16)) { showChrome.toggle() }
    }

    private func handlePageTap(_ fraction: CGFloat, rtl: Bool) {
        let step = ComicPagePositionPolicy.tapStep(fraction, rtl: rtl)
        guard step != 0 else { toggleComicChrome(); return }
        let target = currentPageIndex + step
        if pages.indices.contains(target) {
            pageDirection = step
            withAnimation(reducesMotion ? nil : .easeInOut(duration: 0.16)) { currentPageIndex = target }
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
        VStack {
            // Top Bar
            HStack(spacing: 16) {
                Button {
                    flushComicPosition()
                    if let onRequestExit { onRequestExit() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("comic.return")
                .accessibilityLabel("返回书籍详情")

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
        if let chapter = currentChapter {
                        Text(chapter.title)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(ComicChromePalette.secondaryInkOpacity))
                            .lineLimit(1)
                            .accessibilityIdentifier("comic.chapterTitle")
                    }
                }

                Spacer()

                ReaderNativeMenuButton(menuIdentity: comicMenuIdentity, makeMenu: { comicDisplayMenu },
                    foregroundColor: .white, backgroundColor: .clear, systemImage: readingMode.systemImage,
                    accessibilityIdentifier: "comic.readingMode", accessibilityLabel: "阅读模式与显示设置")
                    .frame(width: 44, height: 44)
                    .background(ComicChromePalette.controlFill, in: Circle())

                // Chapter Drawer Button
                Button {
                    showChapterDrawer = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(ComicChromePalette.controlFill, in: Circle())
                }
                .accessibilityIdentifier("comic.chapters")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(ComicChromeSurface(shape: Rectangle()))

            Spacer()

            // Bottom Bar
            VStack(spacing: 12) {
                // Page Scrubber Slider
                if pages.count > 1 {
                    HStack(spacing: 12) {
                        Text("\(currentPageIndex + 1)")
                            .accessibilityIdentifier("comic.pageNumber")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 32, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { Double(currentPageIndex) },
                                set: { val in
                                    let target = Int(val.rounded())
                                    if target != currentPageIndex && target < pages.count {
                                        currentPageIndex = target
                                        scrollTargetIndex = target
                                    }
                                }
                            ),
                            in: 0...Double(max(pages.count - 1, 1)),
                            step: 1
                        )
                        .tint(.white.opacity(ComicChromePalette.secondaryInkOpacity))

                        Text("\(pages.count) P")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white.opacity(ComicChromePalette.secondaryInkOpacity))
                            .frame(width: 40, alignment: .leading)
                    }
                }

                // Brightness & Dimming Control Bar
                HStack(spacing: 12) {
                    Image(systemName: "sun.min.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))

                    Slider(
                        value: Binding(
                            get: { 1.0 - dimmingLevel },
                            set: { dimmingLevel = max(0.0, min(1.0 - $0, 0.8)) }
                        ),
                        in: 0.2...1.0
                    )
                    .tint(.yellow.opacity(0.85))

                    Image(systemName: "sun.max.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Divider()
                    .background(Color.white.opacity(0.12))

                HStack(spacing: 20) {
                    Button {
                        if currentChapterIndex > 0 {
                            loadChapter(at: currentChapterIndex - 1, startsAtEnd: true)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward")
                            Text("上一话")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(currentChapterIndex > 0 ? .white : .white.opacity(0.3))
                    }
                    .disabled(currentChapterIndex <= 0)

                    Spacer()

                    // Quick Jump to start or end
                    Button {
                        currentPageIndex = 0
                        scrollTargetIndex = 0
                    } label: {
                        Text("首页")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }

                    Button {
                        let last = max(pages.count - 1, 0)
                        currentPageIndex = last
                        scrollTargetIndex = last
                    } label: {
                        Text("末页")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    Button {
                        if currentChapterIndex + 1 < chapters.count {
                            loadChapter(at: currentChapterIndex + 1)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("下一话")
                            Image(systemName: "chevron.forward")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(currentChapterIndex + 1 < chapters.count ? .white : .white.opacity(0.3))
                    }
                    .disabled(currentChapterIndex + 1 >= chapters.count)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(ComicChromeSurface(shape: Rectangle()))
        }
        .transition(.opacity)
    }

    private var comicMenuIdentity: String {
        "\(currentChapterIndex)|\(readingMode.rawValue)|\(showSystemStatusBar)|\(statusPosition)|\(appState.chapterDownloadCoordinator.isRunning(bookID: bookID))"
    }

    private var comicDisplayMenu: UIMenu {
        let modes = ComicReadingMode.allCases.map { mode in
            UIAction(title: mode.rawValue, image: UIImage(systemName: mode.systemImage),
                     state: readingMode == mode ? .on : .off) { _ in readingMode = mode }
        }
        let status = UIAction(title: "显示系统原生状态栏", state: showSystemStatusBar ? .on : .off) { _ in
            showSystemStatusBar.toggle()
        }
        let positions = [("仅页脚", "bottom"), ("仅页眉", "top"), ("页眉+页脚", "both")].map { title, value in
            UIAction(title: title, state: statusPosition == value ? .on : .off) { _ in statusPosition = value }
        }
        var groups = [UIMenu(title: "阅读模式", options: .displayInline, children: modes),
                      UIMenu(title: "状态栏与页眉", options: .displayInline, children: [status] + positions)]
        if let chapter = currentChapter, source.bookSourceUrl != "local://comic",
           !ComicOfflineArchive.isOfflineChapter(chapter) {
            let isRunning = appState.chapterDownloadCoordinator.isRunning(bookID: bookID)
            let download = UIAction(title: isRunning ? "停止漫画下载" : "下载本话供离线阅读",
                image: UIImage(systemName: isRunning ? "stop.circle" : "arrow.down.circle")) { _ in
                if isRunning { appState.chapterDownloadCoordinator.cancel(bookID: bookID) }
                else { downloadCurrentChapter(chapter) }
            }
            groups.append(UIMenu(options: .displayInline, children: [download]))
        }
        return UIMenu(children: groups)
    }

    private var chapterDrawerSheet: some View {
        NavigationStack {
            List {
                ForEach(filteredChapterIndices, id: \.self) { idx in
                    let chapter = chapters[idx]
                    Button {
                        loadChapter(at: idx)
                        showChapterDrawer = false
                    } label: {
                        HStack {
                            Text("\(idx + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .leading)
                            Text(chapter.title)
                                .font(.body)
                                .foregroundStyle(idx == currentChapterIndex ? Color.accentColor : .primary)
                                .lineLimit(1)
                            Spacer()
                            if idx == currentChapterIndex {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .searchable(text: $chapterSearchText, prompt: "搜索话数或标题")
            .navigationTitle("漫画目录 (\(chapters.count) 话)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isChapterListReversed.toggle()
                        }
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

    // MARK: - Logic

    private func downloadCurrentChapter(_ chapter: BookChapter) {
        appState.chapterDownloadCoordinator.start(bookID: bookID, source: source, title: bookTitle, chapters: [chapter],
            engine: engine, cacheStore: appState.chapterContentCacheStore, purifyRules: appState.purifyRuleStore.enabledPatterns)
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

        timeoutTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
            guard generation == loadGeneration, isLoading else { return }
            loadGeneration &+= 1
            chapterTask?.cancel()
            isLoading = false
            errorMessage = "漫画章节请求超过 30 秒，可重试或返回换源"
        }
        chapterTask = Task {
            if let localEngine = engine as? LocalComicSourceEngine {
                timeoutTask?.cancel()
                isLoading = false
                let localPages = localEngine.pages(for: chapter)
                guard !localPages.isEmpty else {
                    errorMessage = "本地漫画图片不存在，请返回书架重新导入。"
                    return
                }
                let resources = ComicChapterResources(offlinePages: localPages)
                showChapter(resources, index: index, savedAnchor: resolveChapterAnchor(resources, at: index,
                    fallbackPage: savedPage, restoresPosition: shouldResume), startsAtEnd: startsAtEnd)
                return
            }
            let isOfflineChapter = ComicOfflineArchive.isOfflineChapter(chapter)
            if !ignoresCache || isOfflineChapter {
                let offlinePages = await appState.comicOfflineArchive.pages(sourceURL: source.bookSourceUrl, chapter: chapter)
                guard !Task.isCancelled, generation == loadGeneration else { return }
                if let offlinePages {
                    timeoutTask?.cancel()
                    isLoading = false
                    let resources = ComicChapterResources(offlinePages: offlinePages)
                    showChapter(resources, index: index, savedAnchor: resolveChapterAnchor(resources, at: index,
                        fallbackPage: savedPage, restoresPosition: shouldResume), startsAtEnd: startsAtEnd)
                    return
                }
                if isOfflineChapter {
                    timeoutTask?.cancel()
                    isLoading = false
                    errorMessage = "离线图片已丢失，请返回详情页重新下载本话。"
                    return
                }
            }
            let cached = appState.chapterContentCacheStore.content(
                sourceURL: source.bookSourceUrl, chapter: chapter, purifyRules: rules)
            let cachedResources = await Self.resolveResources(cached)
            guard !Task.isCancelled else { return }
            let isCacheHit = !ignoresCache && cachedResources?.canReuseFromCache == true
            let result: Result<ChapterContent, SourceEngineError>
            if isCacheHit, let cached { result = .success(cached) }
            else { result = await engine.getContent(source: source, chapter: chapter) }
            let resources: ComicChapterResources?
            if isCacheHit {
                resources = cachedResources
            } else if case .success(let content) = result {
                resources = await Self.resolveResources(content)
            } else { resources = nil }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                // A stale response from a previously selected chapter must not
                // replace the chapter the user is reading now.
                guard generation == self.loadGeneration else { return }
                self.timeoutTask?.cancel()
                self.isLoading = false
                switch result {
                case .success(let content):
                    if let resources, !resources.pages.isEmpty {
                        if !isCacheHit, resources.canReuseFromCache {
                            appState.chapterContentCacheStore.save(content, sourceURL: source.bookSourceUrl, purifyRules: rules)
                        }
                        let target = ignoresCache && index == self.currentChapterIndex && !self.pages.isEmpty
                            ? self.currentPageIndex : savedPage
                        let restores = shouldResume || (ignoresCache && index == self.currentChapterIndex)
                        self.showChapter(resources, index: index, savedAnchor: self.resolveChapterAnchor(resources,
                            at: index, fallbackPage: target, restoresPosition: restores), startsAtEnd: startsAtEnd)
                        if ignoresCache { self.resourceRevision &+= 1 }
                    } else {
                        self.errorMessage = "未在当前章节解析到漫画图片"
                    }
                case .failure(let error):
                    if self.pages.isEmpty, let cachedResources, !cachedResources.pages.isEmpty {
                        self.showChapter(cachedResources, index: index, savedAnchor: self.resolveChapterAnchor(cachedResources,
                            at: index, fallbackPage: savedPage, restoresPosition: shouldResume), startsAtEnd: startsAtEnd)
                    }
                    self.errorMessage = error.displayMessage
                }
            }
        }
    }

    private static func resolveResources(_ content: ChapterContent?) async -> ComicChapterResources? {
        guard let content, !Task.isCancelled else { return nil }
        return await Task.detached(priority: .userInitiated) { ComicChapterResources(content: content) }.value
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
        currentChapterIndex = index
        imageHeaders = SourceRequestBuilder().imageRequestHeaders(for: source, chapterURL: chapters[index].url)
        pendingChapterIndex = nil
        pages = resources.pages
        stripRequests = resources.pages.map { ComicImageRequest(url: $0.url, headers: pageRequestHeaders($0)) }
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
        let indices = ComicPagePositionPolicy.neighbours(of: currentPageIndex, count: pages.count, direction: pageDirection)
        let requests = indices.map { page in (pages[page].url, pageRequestHeaders(pages[page])) }
        for (address, headers) in requests {
            guard !Task.isCancelled else { return }
            guard let url = URL(string: address) else { continue }
            _ = await RemoteImageLoader.shared.comicPage(for: url, headers: headers, maxPixelSize: ComicPagePositionPolicy.maxImagePixels)
        }
    }

    private func prefetchNextChapter(at index: Int) async {
        guard !ProcessInfo.processInfo.isLowPowerModeEnabled,
              ProcessInfo.processInfo.thermalState.rawValue < 2,
              pendingChapterIndex == nil, chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        guard !ComicOfflineArchive.isOfflineChapter(chapter),
              !(await appState.comicOfflineArchive.hasManifest(sourceURL: source.bookSourceUrl, chapter: chapter)),
              !Task.isCancelled, nextChapterPrefetchIndex == index else { return }
        let rules = appState.purifyRuleStore.enabledPatterns
        guard !appState.chapterContentCacheStore.isCached(sourceURL: source.bookSourceUrl, chapter: chapter, purifyRules: rules) else { return }
        guard case .success(let loaded) = await engine.getContent(source: source, chapter: chapter),
              !Task.isCancelled, pendingChapterIndex != index, nextChapterPrefetchIndex == index else { return }
        let isComplete = await Task.detached(priority: .utility) { ComicChapterResources(content: loaded).canReuseFromCache }.value
        guard isComplete, !Task.isCancelled, pendingChapterIndex != index, nextChapterPrefetchIndex == index else { return }
        appState.chapterContentCacheStore.save(loaded, sourceURL: source.bookSourceUrl, purifyRules: rules)
    }

    private func pageRequestHeaders(_ page: ComicPage) -> [String: String] {
        guard URL(string: page.url)?.isFileURL != true else { return [:] }
        return ComicImageRequest(url: page.url, headers: page.headers)
            .mergingHeaders(imageHeaders, chapterURL: currentChapter?.url ?? source.cleanSourceURL)
    }

    private var comicHeader: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 12) {
                Text(currentChapter?.title ?? bookTitle)
                    .lineLimit(1)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer(minLength: 8)

                Text(context.date, format: .dateTime.hour().minute())
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
}

// MARK: - Comic Page Image with Pinch-to-Zoom

private struct ComicPageImageView: View {
    let url: String
    let pageNumber: Int
    let totalPages: Int
    let headers: [String: String]
    let resourceRevision: Int
    var usesNativeZoom = false
    var onTap: (CGFloat) -> Void
    var onInspect: ((UIImage) -> Void)? = nil
    let onRefreshAddresses: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    @State private var loaded: (request: ComicImageRequest, image: UIImage)?
    @State private var failure: ComicImageFailure?
    @State private var attempt = 0

    private var request: ComicImageRequest { ComicImageRequest(url: url, headers: headers) }
    private var image: UIImage? {
        if let loaded, loaded.request == request { return loaded.image }
        guard let address = URL(string: url) else { return nil }
        return RemoteImageLoader.shared.cachedComicPage(for: address, headers: headers, maxPixelSize: ComicPagePositionPolicy.maxImagePixels)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            if let failure {
                Image(systemName: "photo.badge.exclamationmark").font(.title2)
                Text("第 \(pageNumber) 页加载失败").font(.subheadline)
                Text(failure.message)
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                Button("重新加载这一页") { attempt += 1 }
                    .buttonStyle(.bordered).frame(minHeight: 44)
                if failure.canRefreshAddress {
                    Button("重新获取图片地址", action: onRefreshAddresses)
                        .frame(minHeight: 44)
                }
            } else {
                ProgressView().tint(.white)
                Text("正在加载第 \(pageNumber) / \(totalPages) 页").font(.caption)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, minHeight: 320)
        .background(Color.white.opacity(0.04))
    }

    var body: some View {
        ZStack {
            if let image {
                if usesNativeZoom {
                    ComicPageZoomView(image: image, reducesMotion: reducesMotion, onFitTap: onTap)
                } else {
                    Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                        .onTapGesture(count: 2) { onInspect?(image) }
                        .onTapGesture { onTap(0.5) }
                        .accessibilityAction(named: Text("查看大图")) { onInspect?(image) }
                }
            } else {
                placeholder.onTapGesture { onTap(0.5) }
            }
        }
        .task(id: ComicPageLoadIdentity(request: request, attempt: attempt, resourceRevision: resourceRevision)) {
            failure = nil
            let requested = request
            guard let imageURL = URL(string: requested.url) else { failure = .invalidResponse; return }
            let result = await RemoteImageLoader.shared.comicPage(for: imageURL, headers: requested.headers,
                maxPixelSize: ComicPagePositionPolicy.maxImagePixels)
            guard !Task.isCancelled else { return }
            switch result {
            case .success(let image): loaded = (requested, image)
            case .failure(let error): failure = error
            }
        }
    }
}

private struct ComicInspectedPage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private struct ComicPageLoadIdentity: Equatable {
    let request: ComicImageRequest
    let attempt: Int
    let resourceRevision: Int
}

private struct ComicVisiblePageKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
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
