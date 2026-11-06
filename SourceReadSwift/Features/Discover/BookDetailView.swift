import SwiftUI
import UIKit

struct BookDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var detailHero
    @AppMotion private var motion
    @State private var isHeaderCollapsed = false
    @State private var hasArrived = false
    @Environment(\.readingCoverHandoff) private var incomingCoverHandoff
    @StateObject private var detailCoverHandoff = ReadingCoverHandoff()
    @AppStorage("settings.readingDeskEnabled") private var readingDeskEnabled = true
    let initialBook: SearchBook
    var availableSources: [SearchBook] = []
    @State private var book: SearchBook
    @State private var detail: BookDetail?
    @State private var chapters: [BookChapter] = []
    @State private var loadGeneration = UUID()
    @State private var tocExpansionTask: Task<Void, Never>?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var comicDownloadRequest: UUID?
    @State private var comicDownloadError: String?
    @State private var previewPosition: ReaderPreviewPosition?
    @State private var isSavingShelfPosition = false
    @State private var hasPromptedAddAfterPreview = false
    @State private var showAddAfterPreviewPrompt = false
    @State private var isAscending = true
    @State private var showAllChapters = false
    @State private var showAudioPlayer = false
    @State private var showComicReader = false
    @State private var showVideoPlayer = false
    private struct ReadingRoute {
        let chapter: BookChapter
        let showsTitlePage: Bool
    }
    @State private var readingRoute: ReadingRoute?
    @State private var selectedChapterIndexForReader = 0

    private var sourceKind: BookSourceKind {
        if localShelfBook?.sourceURL == "local://comic" { return .comic }
        if let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(detail?.mediaKind ?? book.mediaKind) {
            return source.sourceKind
        }
        return .text
    }

    /// The bookshelf record behind a local import. `SearchBook.id` is derived as
    /// `sourceURL|bookURL`, so it never equals the stored `local|<UUID>` id; the
    /// detail screen therefore has to resolve the record through `bookUrl`.
    private var localShelfBook: BookshelfBook? {
        guard book.sourceUrl.hasPrefix("local://") else { return nil }
        return appState.bookshelfStore.localBook(matching: book.bookUrl)
    }

    /// Reader handoff id. Local books must pass the stored `local|<UUID>` id,
    /// otherwise `bookshelfStore.book(id:)` inside the reader finds nothing and
    /// every chapter opens empty.
    private var readerBookID: String {
        if let shelfBook = localShelfBook { return shelfBook.id }
        return appState.bookshelfStore.contains(book) ? book.id : "\(book.sourceUrl)|\(book.bookUrl)"
    }

    private var downloadRecord: ChapterDownloadRecord? {
        let record = appState.chapterDownloadStore.record(bookID: book.id)
        if sourceKind == .comic, record?.hasComicImageArchive != true { return nil }
        return record
    }

    private var isDownloading: Bool {
        comicDownloadRequest != nil || appState.chapterDownloadCoordinator.isRunning(bookID: book.id)
    }

    private var isBookInBookshelf: Bool {
        appState.bookshelfStore.contains(book)
    }

    private var hasStartedPreview: Bool { previewPosition?.bookID == readerBookID }

    /// The detail header is the first place all source results meet. When the
    /// primary result has no cover but a sibling source does, show the sibling
    /// cover instead of a blank placeholder.
    private var displayBook: SearchBook {
        // A retained source cover stays the same edition through push and pop.
        // A deliberate source switch still uses the newly selected edition.
        let initialCover = book.coverUrl?.nilIfEmpty
        let address = CoverURLResolver.url(from: initialCover, base: book.bookUrl, fallbackBase: book.sourceUrl)
        let retainedCover = address.flatMap { incomingCoverHandoff?.image(for: $0) } != nil ? initialCover : nil
        let cover = retainedCover ?? detail?.coverUrl?.nilIfEmpty ?? initialCover
            ?? availableSources.compactMap({ $0.coverUrl?.nilIfEmpty }).first
        return SearchBook(
            name: detail?.name.nilIfEmpty ?? book.name,
            author: detail?.author?.nilIfEmpty ?? book.author,
            coverUrl: cover,
            bookUrl: book.bookUrl,
            sourceName: book.sourceName,
            sourceUrl: book.sourceUrl,
            intro: detail?.intro?.nilIfEmpty ?? book.intro,
            kind: book.kind,
            lastChapter: book.lastChapter,
            wordCount: detail?.wordCount?.nilIfEmpty ?? book.wordCount,
            checkKeyWord: book.checkKeyWord,
            mediaKind: detail?.mediaKind ?? book.mediaKind
        )
    }

    private var targetReadingChapter: BookChapter? {
        if let currentIdx = appState.bookshelfStore.book(id: readerBookID)?.currentChapterIndex,
           chapters.indices.contains(currentIdx) {
            return chapters[currentIdx]
        }
        if let position = previewPosition, position.bookID == readerBookID,
           let chapter = chapters.first(where: { $0.index == position.chapterIndex }) { return chapter }
        return chapters.first
    }

    private var displayedChapters: [BookChapter] {
        isAscending ? Array(chapters.prefix(20)) : Array(chapters.reversed().prefix(20))
    }

    private var shelfReadingContext: String? {
        guard let shelf = appState.bookshelfStore.book(id: readerBookID),
              shelf.lastReadAt != nil, shelf.currentChapterTitle?.nilIfEmpty != nil else { return nil }
        return ReadingHeroStatus.chapter(for: shelf)
    }

    private var readerHeroID: String { "reader|" + book.id }
    private var coverHandoff: ReadingCoverHandoff { incomingCoverHandoff ?? detailCoverHandoff }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: readingDeskEnabled ? 16 : AppLayout.sectionGap) {
                if readingDeskEnabled {
                    BookDetailHero(book: displayBook, readerSourceID: readerHeroID,
                        namespace: detailHero, readingContext: shelfReadingContext)
                } else {
                    BookDetailHeader(book: displayBook)
                }

                if let target = targetReadingChapter {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        readAction(target)
                        shelfAction
                    }
                    .offset(y: hasArrived || motion.reducesMotion ? 0 : 8)
                    .animation(motion.arrivalAnimation(stage: 2), value: hasArrived)
                }

                if availableSources.count > 1 {
                    sourceSwitchBar
                }

                if isLoading {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text("正在加载详情")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .podcastCard()
                } else if let errorMessage {
                    EmptyStateCard(
                        systemImage: "exclamationmark.triangle",
                        title: "详情加载失败",
                        message: errorMessage
                    )
                } else if let detail {
                    detailCard(detail)
                    if book.sourceName == "Z-Library" || book.bookUrl.hasPrefix("zlib://") {
                        zlibraryActionCard
                    } else {
                        switch sourceKind {
                        case .audio:
                            audioBookActionCard
                        case .comic:
                            comicActionCard
                        case .video:
                            videoActionCard
                        case .text:
                            EmptyView()
                        }
                        chapterList
                    }
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .environment(\.readingCoverHandoff, readingDeskEnabled ? coverHandoff : nil)
        .accessibilityIdentifier("bookDetail.scroll")
        .coordinateSpace(name: "bookDetailScroll")
        .onPreferenceChange(BookDetailHeaderOffset.self) { bottom in
            let collapsed = bottom < 60
            if collapsed != isHeaderCollapsed { isHeaderCollapsed = collapsed }
        }
        .pageBackground()
        .navigationTitle(isHeaderCollapsed ? book.name : "书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if sourceKind == .text, let target = targetReadingChapter {
                        Button { openReadingRoute(target, showsTitlePage: true) } label: {
                            Label("查看书籍扉页", systemImage: "book.closed")
                        }
                        .accessibilityIdentifier("bookDetail.titlePage")
                    }
                    Button { markAsRead() } label: {
                        Label("标记为已读", systemImage: "checkmark.circle")
                    }
                    Button { isAscending.toggle() } label: {
                        Label(isAscending ? "切换倒序" : "切换正序", systemImage: "arrow.up.arrow.down")
                    }
                    Button { Task { await reload() } } label: {
                        Label("刷新目录", systemImage: "arrow.clockwise")
                    }
                    Button { toggleDownload() } label: {
                        Label(downloadLabel, systemImage: isDownloading ? "stop.circle" : "arrow.down.circle")
                    }
                    .disabled(chapters.isEmpty || book.sourceUrl.hasPrefix("local://"))
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("书籍操作")
            }
        }
        .task {
            guard chapters.isEmpty, errorMessage == nil else { return }
            SourceSwitchCacheStore.shared.remember(books: availableSources + [book])
            await load()
        }
        .task(id: comicDownloadRequest) {
            if let request = comicDownloadRequest { await prepareComicDownload(request: request) }
        }
        .onChange(of: book.id) { _ in comicDownloadRequest = nil }
        .onDisappear { comicDownloadRequest = nil }
        .alert("无法下载全本漫画", isPresented: Binding(
            get: { comicDownloadError != nil }, set: { if !$0 { comicDownloadError = nil } }
        )) {
            Button("关闭", role: .cancel) {}
        } message: {
            Text(comicDownloadError ?? "")
        }
        .navigationDestination(isPresented: Binding(
            get: { readingRoute != nil }, set: { if !$0 { readingRoute = nil } }
        )) {
            if let route = readingRoute {
                if route.showsTitlePage { titlePage(for: route.chapter) }
                else { readDestination(route.chapter, usesDetailHero: true) }
            }
        }
        .sheet(isPresented: $showAllChapters) {
            BookDetailAllChaptersView(
                chapters: chapters,
                book: book,
                bookID: readerBookID,
                localBook: localShelfBook,
                onPreviewPosition: recordPreviewPosition,
                onReaderReturn: { promptToAddAfterPreviewIfNeeded() },
                addPrompt: $showAddAfterPreviewPrompt,
                addBook: addCurrentBookToShelf
            )
        }
        .sheet(isPresented: $showAudioPlayer) {
            AudioBookPlayerView()
        }
        .fullScreenCover(isPresented: $showComicReader) {
            if let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(detail?.mediaKind ?? book.mediaKind) {
                ComicReaderView(
                    bookID: appState.bookshelfStore.contains(book) ? book.id : "\(book.sourceUrl)|\(book.bookUrl)",
                    bookTitle: book.name,
                    source: source,
                    initialChapterIndex: selectedChapterIndexForReader,
                    chapters: chapters,
                    engine: appState.engine,
                    initialPageIndex: previewPosition.flatMap { $0.chapterIndex == selectedChapterIndexForReader ? $0.paragraphIndex : nil },
                    initialComicPosition: previewPosition?.comicPosition,
                    onPreviewPosition: recordPreviewPosition
                )
            }
        }
        .fullScreenCover(isPresented: $showVideoPlayer) {
            if let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(detail?.mediaKind ?? book.mediaKind) {
                VideoPlayerView(
                    bookID: appState.bookshelfStore.contains(book) ? book.id : "\(book.sourceUrl)|\(book.bookUrl)",
                    bookTitle: book.name,
                    source: source,
                    initialChapterIndex: selectedChapterIndexForReader,
                    chapters: chapters,
                    engine: appState.engine
                )
            }
        }
        .onAppear { hasArrived = true }
        .onChange(of: readingRoute != nil) { if !$0 { promptToAddAfterPreviewIfNeeded() } }
        .onChange(of: showAllChapters) { if !$0 { promptToAddAfterPreviewIfNeeded() } }
        .onChange(of: showComicReader) { if !$0 { promptToAddAfterPreviewIfNeeded() } }
        .modifier(ReaderPreviewShelfPrompt(isPresented: Binding(
            get: { readingRoute == nil && !showAllChapters && showAddAfterPreviewPrompt }, set: { showAddAfterPreviewPrompt = $0 }
        ), addBook: addCurrentBookToShelf))
    }

    private var shouldShowTitlePage: Bool {
        sourceKind == .text && !hasStartedPreview
            && ReaderLaunchCursor.shouldShowTitlePage(for: appState.bookshelfStore.book(id: readerBookID))
    }

    private var readingActionLabel: String {
        shouldShowTitlePage || (!isBookInBookshelf && !hasStartedPreview) ? "开始阅读" : "继续阅读"
    }

    private func titlePage(for target: BookChapter) -> some View {
        BookTitlePage(book: displayBook, chapterCount: chapters.count, readLabel: readingActionLabel) {
            readDestination(target, usesDetailHero: false)
        }
        .onAppear { promptToAddAfterPreviewIfNeeded(onTitlePage: true) }
        .modifier(ReaderPreviewShelfPrompt(isPresented: Binding(
            get: { readingRoute?.showsTitlePage == true && showAddAfterPreviewPrompt },
            set: { showAddAfterPreviewPrompt = $0 }
        ), addBook: addCurrentBookToShelf))
    }

    @ViewBuilder private func readDestination(_ target: BookChapter, usesDetailHero: Bool) -> some View {
        Group {
            if let shelfBook = localShelfBook {
                BookshelfReaderGatewayView(book: shelfBook, initialChapterIndex: target.index,
                    onRequestExit: usesDetailHero ? closeDirectReadingRoute : nil)
            } else {
                let shelf = appState.bookshelfStore.book(id: readerBookID)
                let preview = previewPosition.flatMap { $0.bookID == readerBookID && $0.chapterIndex == target.index ? $0 : nil }
                ChapterLoadingView(bookID: readerBookID, sourceUrl: book.sourceUrl,
                    chapter: target, totalChapters: chapters.count, chapters: chapters,
                    initialParagraphIndex: shelf?.currentChapterIndex == target.index ? shelf?.currentParagraphIndex : preview?.paragraphIndex,
                    onPreviewPosition: recordPreviewPosition, onRequestExit: usesDetailHero ? closeDirectReadingRoute : nil)
            }
        }
        // Deep TOC scrolling or the title page has no visible detail hero source.
        .readerOpeningPresentation(for: sourceKind == .text ? BookshelfBook(searchBook: displayBook) : nil,
            coverFrame: coverHandoff.frame(for: BookshelfBook(searchBook: displayBook)), usesSystemReturnSurface: true)
        .bookHeroDestination(readerHeroID, in: detailHero,
            enabled: usesDetailHero && !isHeaderCollapsed && sourceKind == .text)
        .environment(\.readingCoverHandoff, readingDeskEnabled ? coverHandoff : nil)
    }

    private func openReadingRoute(_ chapter: BookChapter, showsTitlePage: Bool) {
        guard readingRoute == nil else { return }
        readingRoute = ReadingRoute(chapter: chapter, showsTitlePage: showsTitlePage)
    }

    /// This button owns only the detail's nested route, never the bookshelf route.
    private func closeDirectReadingRoute() {
        guard readingRoute?.showsTitlePage == false else { return }
        readingRoute = nil
    }

    private func readAction(_ target: BookChapter) -> some View {
        Button {
            if sourceKind == .comic && localShelfBook == nil {
                selectedChapterIndexForReader = target.index
                showComicReader = true
            } else {
                openReadingRoute(target, showsTitlePage: shouldShowTitlePage)
            }
        } label: {
            Label(readingActionLabel, systemImage: "book")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 12)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(BookOpenPressStyle())
        .accessibilityIdentifier("bookDetail.read")
    }

    private var shelfAction: some View {
        Button { addCurrentBookToShelf() } label: {
            Label(isSavingShelfPosition ? "正在保存" : isBookInBookshelf ? "已在书架" : "加入书架", systemImage: isBookInBookshelf ? "checkmark" : "plus")
                .font(.subheadline.weight(.medium))
                .frame(minHeight: 44)
                .padding(.horizontal, 12)
                .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(isBookInBookshelf ? .secondary : AppTheme.accent)
        }
        .buttonStyle(AppPressStyle())
        .disabled(isSavingShelfPosition)
        .accessibilityIdentifier("bookDetail.shelfAction")
        .accessibilityValue(isSavingShelfPosition ? "正在保存" : isBookInBookshelf
            ? (appState.bookshelfStore.lastError == nil ? "已保存" : "保存失败") : "未加入")
    }

    @State private var isDownloadingZlib = false
    @State private var zlibDownloadError: String?

    private var zlibraryActionCard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(AppTheme.accent)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Z-Library 全球图书源")
                        .font(.headline)
                    Text("格式：EPUB  ·  点击即可高速下载并进入沉浸阅读")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            if let zlibDownloadError {
                Text(zlibDownloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await downloadAndOpenZlibBook()
                }
            } label: {
                HStack {
                    if isDownloadingZlib {
                        ProgressView()
                            .tint(.white)
                            .padding(.trailing, 6)
                        Text("正在高速下载中...")
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(appState.bookshelfStore.contains(book) ? "已在书架，重新下载/阅读" : "立即下载并加入书架")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(AppPressStyle())
            .disabled(isDownloadingZlib)
        }
        .podcastCard()
    }

    private func downloadAndOpenZlibBook() async {
        guard !isDownloadingZlib else { return }
        isDownloadingZlib = true
        zlibDownloadError = nil
        defer { isDownloadingZlib = false }

        let raw = book.bookUrl.replacingOccurrences(of: "zlib://", with: "")
        let parts = raw.split(separator: "/")
        guard parts.count >= 2 else {
            zlibDownloadError = "无效的图书链接"
            return
        }
        let bookID = String(parts[0])
        let hash = String(parts[1])

        do {
            let fileURL = try await ZlibraryEngine.shared.downloadBook(bookID: bookID, hash: hash, title: book.name)
            let parsed = try LocalEPUBBookParser().parse(fileURL: fileURL)
            appState.bookshelfStore.addLocalTextBook(parsed)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            zlibDownloadError = "下载失败：\(error.localizedDescription)"
        }
    }

    private func detailCard(_ detail: BookDetail) -> some View {
        BookDetailSummary(detail: detail)
    }

    private var audioBookActionCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(detail?.mediaKind ?? book.mediaKind) {
                AudioBookPlaybackCoordinator.shared.startBook(
                    book: book,
                    source: source,
                    chapters: chapters,
                    initialChapterIndex: 0,
                    engine: appState.engine
                )
                showAudioPlayer = true
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.accent)
                        .frame(width: 48, height: 48)
                    Image(systemName: "headphones")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("有声书收听专区")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("支持后台锁屏播放、定时暂停与多倍速调节")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.vertical, 4)
        }
        .podcastCard()
    }

    private var comicActionCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selectedChapterIndexForReader = targetReadingChapter?.index ?? 0
            showComicReader = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 48, height: 48)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("漫画连载专区")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("支持条漫瀑布流、双向翻页与高精双指缩放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "book.pages.fill")
                    .font(.title2)
                    .foregroundStyle(Color.orange)
            }
            .padding(.vertical, 4)
        }
        .podcastCard()
    }

    private var videoActionCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            selectedChapterIndexForReader = 0
            showVideoPlayer = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 48, height: 48)
                    Image(systemName: "play.tv")
                        .font(.title3)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("影视视频专区")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("支持手势调光控音、无级倍速与剧集选集")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.red)
            }
            .padding(.vertical, 4)
        }
        .podcastCard()
    }

    private var chapterList: some View {
        let visibleChapters = displayedChapters
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("目录")
                    .font(.title2.bold())
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    isAscending.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(isAscending ? "正序" : "倒序")
                    }
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(AppTheme.accent.opacity(0.1), in: Capsule())
                }
                .buttonStyle(AppPressStyle())

                if canDownloadTextChapters {
                    chapterDownloadMenu
                } else if sourceKind == .comic, localShelfBook == nil, !chapters.isEmpty {
                    Button(action: toggleDownload) {
                        Image(systemName: isDownloading ? "stop.circle" : "arrow.down.circle")
                            .font(.title3)
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(AppPressStyle())
                    .accessibilityLabel(downloadLabel)
                    .accessibilityIdentifier("bookDetail.downloadComic")
                }

                Text("\(chapters.count) 章")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.secondary)
            }
            if canDownloadTextChapters || sourceKind == .comic, let record = downloadRecord {
                chapterDownloadStatus(record)
            }
            if comicDownloadRequest != nil {
                ProgressView("正在核对全本目录")
                    .font(.caption)
            }

            VStack(spacing: 0) {
                ForEach(visibleChapters.indices, id: \.self) { index in
                    let chapter = visibleChapters[index]
                    if let volume = ChapterListPresenter.volumeHeader(at: index, in: visibleChapters) {
                        Text(volume)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 4)
                    }
                    switch sourceKind {
                    case .audio:
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            if let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(detail?.mediaKind ?? book.mediaKind) {
                                AudioBookPlaybackCoordinator.shared.startBook(
                                    book: book,
                                    source: source,
                                    chapters: chapters,
                                    initialChapterIndex: chapter.index,
                                    engine: appState.engine
                                )
                                showAudioPlayer = true
                            }
                        } label: {
                            HStack {
                                Image(systemName: "headphones")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.accent)
                                chapterTitleLabel(chapter)
                                Spacer()
                                Image(systemName: "play.circle")
                                    .font(.body)
                                    .foregroundStyle(AppTheme.accent)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AppPressStyle())

                    case .comic:
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedChapterIndexForReader = chapter.index
                            showComicReader = true
                        } label: {
                            HStack {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                chapterTitleLabel(chapter)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AppPressStyle())

                    case .video:
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedChapterIndexForReader = chapter.index
                            showVideoPlayer = true
                        } label: {
                            HStack {
                                Image(systemName: "play.tv")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                chapterTitleLabel(chapter)
                                Spacer()
                                Image(systemName: "play.fill")
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AppPressStyle())

                    case .text:
                        // Local imports have no book source, and ChapterLoadingView
                        // bails out with 「找不到书源」 for them. They open through the
                        // same local reader route the shelf uses instead.
                        Button { openReadingRoute(chapter, showsTitlePage: false) } label: { textChapterRowLabel(chapter) }
                            .buttonStyle(AppPressStyle())
                    }

                    if index < visibleChapters.count - 1 {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))

            if chapters.count > visibleChapters.count {
                Button {
                    showAllChapters = true
                } label: {
                    Label("查看全部 \(chapters.count) 章", systemImage: "list.number")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func textChapterRowLabel(_ chapter: BookChapter) -> some View {
        HStack {
            chapterTitleLabel(chapter)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    private func chapterTitleLabel(_ chapter: BookChapter) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let metadata = ChapterListPresenter.metadataLabel(chapter) {
                    Text(metadata)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if chapter.isVip {
                Text("VIP")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private func load(ignoreCache: Bool = false) async {
        guard !isLoading else { return }
        if book.sourceName == "Z-Library" || book.bookUrl.hasPrefix("zlib://") {
            isLoading = true
            defer { isLoading = false }
            detail = BookDetail(
                name: book.name,
                author: book.author,
                coverUrl: book.coverUrl,
                bookUrl: book.bookUrl,
                tocUrl: nil,
                sourceName: book.sourceName,
                sourceUrl: book.sourceUrl,
                intro: book.intro,
                latestChapter: "全本"
            )
            chapters = [
                BookChapter(
                    title: "全本阅读 (EPUB)",
                    url: book.bookUrl,
                    bookUrl: book.bookUrl,
                    index: 0,
                    isVip: false
                )
            ]
            return
        }

        // 本地书（TXT / EPUB 导入）没有书源。以前这里继续往下走，
        // `sourceStore.source(for: "local://text")` 必然返回 nil，于是直接落进
        // 「找不到书源：Local」的空状态，章节数显示 0，缓存/标记已读全部空转。
        // 现在本地书走独立分支：章节直接从书架里的 localChapters 来，全程不碰 SourceEngine。
        if book.sourceUrl.hasPrefix("local://") {
            isLoading = true
            defer { isLoading = false }
            let localBook = appState.bookshelfStore.book(id: book.id) ?? localShelfBook
            let localChapters = localBook?.localChapters ?? []
            detail = BookDetail(
                name: book.name,
                author: book.author,
                coverUrl: book.coverUrl,
                bookUrl: book.bookUrl,
                tocUrl: nil,
                sourceName: book.sourceName,
                sourceUrl: book.sourceUrl,
                intro: book.intro,
                latestChapter: localChapters.last?.title ?? "本地导入"
            )
            chapters = localChapters.map { chapter in
                BookChapter(
                    title: chapter.title,
                    url: "\(book.bookUrl)#\(chapter.index)",
                    bookUrl: book.bookUrl,
                    index: chapter.index,
                    isVip: false
                )
            }
            return
        }

        guard let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(detail?.mediaKind ?? book.mediaKind) else {
            errorMessage = "找不到书源：\(book.sourceName)"
            return
        }

        // 目录缓存命中：先把上次的详情 + 目录画出来，网络请求放到后台，
        // 详情页不再为了等 `getChapterList` 的几十页分页而白屏。
        if !ignoreCache,
           let cached = appState.bookTOCacheStore.entry(sourceURL: book.sourceUrl, bookURL: book.bookUrl),
           !cached.chapters.isEmpty {
            if detail == nil { detail = cached.detail }
            chapters = cached.chapters
            errorMessage = nil
            Task { await refreshDetailAndTOC(source: source, reportErrors: false) }
            return
        }

        guard detail == nil || ignoreCache else { return }

        isLoading = true
        await refreshDetailAndTOC(source: source, reportErrors: true)
    }

    /// 拉详情 + 全量目录。首次打开用于填充整页，命中缓存后用于后台刷新；
    /// `reportErrors == false` 时失败保持静默，避免把已经显示出来的目录
    /// 换成一屏红字。
    private enum LoadEvent {
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
                            wordCount: book.wordCount, checkKeyWord: book.checkKeyWord,
                            mediaKind: value.mediaKind ?? book.mediaKind)
                    }
                case .detail(.failure(let error)):
                    if reportErrors && chapters.isEmpty { errorMessage = error.displayMessage }
                case .toc(.success(let value)):
                    chapters = value
                    if detail == nil { detail = placeholder }
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
            if case .success(let value)? = retry { chapters = value; errorMessage = nil }
            else if reportErrors && chapters.isEmpty { errorMessage = "目录加载失败，可刷新重试" }
        }
        guard current() else { return }
        if appState.bookshelfStore.contains(selectedBook), let fetchedDetail {
            appState.bookshelfStore.updateDetails(bookID: selectedBook.id,
                latestChapterTitle: fetchedDetail.latestChapter, intro: fetchedDetail.intro,
                totalChapters: chapters.count, coverURL: fetchedDetail.coverUrl, mediaKind: fetchedDetail.mediaKind)
        }
        isLoading = false
        let cacheDetail = fetchedDetail ?? placeholder
        if detail == nil { detail = cacheDetail }
        if !chapters.isEmpty {
            appState.bookTOCacheStore.save(detail: cacheDetail, chapters: chapters,
                sourceURL: selectedBook.sourceUrl, bookURL: selectedBook.bookUrl, isComplete: !stagedFirstPaint)
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
                  case .success(let full) = result, !full.isEmpty, full.count >= chapters.count else { return }
            chapters = full
            appState.bookTOCacheStore.save(detail: loadedDetail, chapters: full,
                sourceURL: sourceURL, bookURL: bookURL)
        }
    }

    private func reload() async {
        // A source switch supersedes an in-flight load; it must not be dropped
        // by load()'s duplicate-request guard after the page has been cleared.
        loadGeneration = UUID()
        tocExpansionTask?.cancel()
        isLoading = false
        detail = nil
        chapters = []
        errorMessage = nil
        await load(ignoreCache: true)
    }

    private func markAsRead() {
        guard !chapters.isEmpty else { return }
        if !appState.bookshelfStore.contains(book) {
            appState.bookshelfStore.addOrUpdate(displayBook)
        }
        appState.bookshelfStore.updateReadingProgress(
            bookID: readerBookID,
            chapterIndex: max(chapters.count - 1, 0),
            chapterTitle: chapters.last?.title,
            totalChapters: chapters.count
        )
    }

    private var downloadLabel: String {
        if isDownloading { return sourceKind == .comic ? "停止漫画下载" : "停止缓存" }
        guard let record = downloadRecord else { return sourceKind == .comic ? "下载全本漫画" : "缓存全本章节" }
        switch record.status {
        case .completed: return "重新检查离线缓存"
        case .paused: return "继续缓存 \(record.completedCount)/\(record.chapterCount)"
        case .failed: return "重试缓存（失败 \(record.failedCount)）"
        case .cancelled, .queued, .running: return "继续缓存 \(record.completedCount)/\(record.chapterCount)"
        }
    }

    private func toggleDownload() {
        if comicDownloadRequest != nil {
            comicDownloadRequest = nil
            return
        }
        if isDownloading {
            appState.chapterDownloadCoordinator.cancel(bookID: book.id)
            return
        }
        guard !chapters.isEmpty,
              let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(detail?.mediaKind ?? book.mediaKind) else { return }
        if source.sourceKind == .comic {
            comicDownloadRequest = UUID()
            return
        }
        enqueueDownload(source: source, chapters: chapters)
    }

    private func prepareComicDownload(request: UUID) async {
        defer { if comicDownloadRequest == request { comicDownloadRequest = nil } }
        let selectedBook = book
        let engine = appState.engine
        guard let source = appState.sourceStore.source(for: selectedBook.sourceUrl)?.resolvingMediaKind(selectedBook.mediaKind) else {
            comicDownloadError = "找不到漫画书源。请恢复书源后重试。"
            return
        }
        let verified: Result<[BookChapter], SourceEngineError>? = await AsyncTimeout.run(seconds: 30) {
            switch await engine.getBookDetail(source: source, book: selectedBook) {
            case .success(let downloadDetail):
                guard !Task.isCancelled else { return .failure(.network("目录请求已取消")) }
                return await engine.getCompleteChapterList(source: source, book: downloadDetail)
            case .failure(let error): return .failure(error)
            }
        }
        guard !Task.isCancelled, comicDownloadRequest == request, book.id == selectedBook.id else { return }
        switch verified {
        case .some(.success(let complete)) where !complete.isEmpty:
            enqueueDownload(source: source, chapters: complete)
        case .some(.failure(let error)):
            comicDownloadError = String(SourceDiagnosticRedactor.value(error.displayMessage).prefix(240))
        case .some(.success):
            comicDownloadError = "书源目录为空，未开始全本下载。"
        case nil:
            comicDownloadError = "核对目录超时，未开始全本下载。请重试或下载单话。"
        }
    }

    private func enqueueDownload(source: BookSource, chapters: [BookChapter]) {
        appState.chapterDownloadCoordinator.start(
            bookID: book.id,
            source: source,
            title: book.name,
            chapters: chapters,
            engine: appState.engine,
            cacheStore: appState.chapterContentCacheStore,
            purifyRules: appState.purifyRuleStore.enabledPatterns
        )
    }

    private func addCurrentBookToShelf() {
        guard !isBookInBookshelf else { return }
        isSavingShelfPosition = true
        appState.bookshelfStore.addOrUpdate(displayBook)
        if let detail {
            appState.bookshelfStore.updateDetails(
                bookID: book.id,
                latestChapterTitle: detail.latestChapter,
                intro: detail.intro,
                totalChapters: chapters.count,
                coverURL: detail.coverUrl, mediaKind: detail.mediaKind
            )
        }
        if let position = previewPosition, position.bookID == readerBookID {
            appState.bookshelfStore.updateReadingProgress(bookID: position.bookID, chapterIndex: position.chapterIndex,
                chapterTitle: position.chapterTitle, totalChapters: chapters.count, paragraphIndex: position.paragraphIndex,
                comicPosition: position.comicPosition)
        }
        appState.finishReadingWritesInBackground()
        Task { @MainActor in
            await appState.bookshelfStore.waitForPendingWrites()
            isSavingShelfPosition = false
            if let failure = appState.bookshelfStore.lastError {
                errorMessage = "保存书架与阅读位置失败：\(failure)"
            }
        }
    }

    private func recordPreviewPosition(_ position: ReaderPreviewPosition) {
        guard position.bookID == readerBookID, position != previewPosition, !isBookInBookshelf else { return }
        previewPosition = position
    }

    private func promptToAddAfterPreviewIfNeeded(onTitlePage: Bool = false) {
        guard (readingRoute?.showsTitlePage == true) == onTitlePage,
              !hasPromptedAddAfterPreview, previewPosition?.bookID == readerBookID, !isBookInBookshelf else { return }
        hasPromptedAddAfterPreview = true
        showAddAfterPreviewPrompt = true
    }

    init(book: SearchBook, availableSources: [SearchBook] = []) {
        self.initialBook = book
        self.availableSources = availableSources
        self._book = State(initialValue: book)
    }

    private var sourceSwitchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(AppTheme.accent)
            Text("当前书源：\(book.sourceName)")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Menu {
                ForEach(availableSources) { srcBook in
                    Button {
                        guard srcBook.sourceUrl != book.sourceUrl || srcBook.bookUrl != book.bookUrl else { return }
                        book = srcBook
                        Task {
                            await reload()
                        }
                    } label: {
                        HStack {
                            Text(srcBook.sourceName)
                            if srcBook.sourceUrl == book.sourceUrl && srcBook.bookUrl == book.bookUrl {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("换源 (\(availableSources.count))")
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(.systemGray5), in: Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var canDownloadTextChapters: Bool {
        sourceKind == .text && !chapters.isEmpty && !book.sourceUrl.hasPrefix("local://")
    }

    private var chapterDownloadMenu: some View {
        Menu {
            if isDownloading {
                Button(role: .destructive) {
                    appState.chapterDownloadCoordinator.cancel(bookID: book.id)
                } label: {
                    Label("停止缓存", systemImage: "stop.circle")
                }
            } else {
                Button {
                    downloadChapters(limit: 50)
                } label: {
                    Label("缓存后 50 章", systemImage: "arrow.down.to.line")
                }
                Button {
                    downloadChapters(limit: nil)
                } label: {
                    Label("缓存全本", systemImage: "arrow.down.circle")
                }
            }
        } label: {
            Image(systemName: isDownloading ? "arrow.down.circle.fill" : "arrow.down.circle")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("离线缓存")
        .accessibilityIdentifier("bookDetail.chapterDownload")
    }

    private func chapterDownloadStatus(_ record: ChapterDownloadRecord) -> some View {
        let unit = record.hasComicImageArchive == true ? "话" : "章"
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: Double(record.completedCount), total: Double(max(record.chapterCount, 1)))
                .tint(AppTheme.accent)
            HStack(spacing: 8) {
                Text("下载进度 \(record.completedCount)/\(record.chapterCount) \(unit)")
                    .foregroundStyle(.secondary)
                if record.failedCount > 0 {
                    Text("\(record.failedCount) \(unit)失败").foregroundStyle(.red)
                }
            }
            .font(.caption)
        }
    }

    private func downloadChapters(limit: Int?) {
        guard !chapters.isEmpty,
              let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(detail?.mediaKind ?? book.mediaKind) else { return }
        let currentReadingIndex = appState.bookshelfStore.book(id: readerBookID)?.currentChapterIndex ?? 0
        let targets: [BookChapter]
        if let limit {
            targets = Array(chapters.dropFirst(max(currentReadingIndex, 0)).prefix(limit))
        } else {
            targets = chapters
        }
        guard !targets.isEmpty else { return }
        appState.chapterDownloadCoordinator.start(
            bookID: book.id,
            source: source,
            title: book.name,
            chapters: targets,
            engine: appState.engine,
            cacheStore: appState.chapterContentCacheStore,
            purifyRules: appState.purifyRuleStore.enabledPatterns
        )
    }

}

struct ChapterLoadingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerOpeningManaged) private var readerOpeningManaged
    let bookID: String?
    let sourceUrl: String
    let chapter: BookChapter
    var totalChapters: Int? = nil
    var chapters: [BookChapter] = []
    @State private var initialParagraphIndex: Int?
    var openingBook: BookshelfBook? = nil
    var extraToolbarActions: () -> AnyView = { AnyView(EmptyView()) }
    var onRequestSourceSwitch: (() -> Void)?
    var onRequestBookDetail: (() -> Void)? = nil
    var onPreviewPosition: ((ReaderPreviewPosition) -> Void)? = nil
    var onRequestExit: (() -> Void)? = nil
    @State private var content: ChapterContent?
    @State private var loadedChapter: BookChapter?
    @State private var currentChapter: BookChapter?
    @State private var currentParagraphIndex: Int? = nil
    @State private var errorMessage: String?
    @State private var isUsingStaleCache = false
    @State private var isCachingNext = false
    @State private var autoplaySpeechAfterHandoff = false
    @State private var autoplayAutoScrollAfterHandoff = false
    @State private var showReaderChromeAfterChapterSelection = false
    @State private var showBookDetailSheet = false
    @State private var chapterLoadingTabChromeOwner = UUID()
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount

    private var effectiveChapter: BookChapter {
        currentChapter ?? chapter
    }

    private var resolvedChapterSource: BookSource? {
        let kind = bookID.flatMap { appState.bookshelfStore.book(id: $0)?.mediaKind } ?? openingBook?.mediaKind
        return appState.sourceStore.source(for: sourceUrl)?.resolvingMediaKind(kind)
    }

    var body: some View {
        Group {
            if let source = resolvedChapterSource, source.sourceKind != .text {
                switch source.sourceKind {
                case .audio:
                    AudioBookPlayerView()
                        .onAppear {
                            let searchBook = SearchBook(
                                name: effectiveChapter.title,
                                author: nil,
                                coverUrl: nil,
                                bookUrl: effectiveChapter.bookUrl,
                                sourceName: source.bookSourceName,
                                sourceUrl: source.bookSourceUrl,
                                mediaKind: source.sourceKind
                            )
                            AudioBookPlaybackCoordinator.shared.startBook(
                                bookID: bookID,
                                book: searchBook,
                                source: source,
                                chapters: chapters.isEmpty ? [effectiveChapter] : chapters,
                                initialChapterIndex: effectiveChapter.index,
                                engine: appState.engine,
                                bookshelfStore: appState.bookshelfStore
                            )
                        }
                case .comic:
                    ComicReaderView(
                        bookID: bookID ?? "",
                        bookTitle: effectiveChapter.title,
                        source: source,
                        initialChapterIndex: effectiveChapter.index,
                        chapters: chapters.isEmpty ? [effectiveChapter] : chapters,
                        engine: appState.engine
                    )
                case .video:
                    VideoPlayerView(
                        bookID: bookID ?? "",
                        bookTitle: effectiveChapter.title,
                        source: source,
                        initialChapterIndex: effectiveChapter.index,
                        chapters: chapters.isEmpty ? [effectiveChapter] : chapters,
                        engine: appState.engine
                    )
                case .text:
                    EmptyView()
                }
            } else if let loadedContent = content ?? (errorMessage == nil ? cachedOpeningContent : nil) {
                readerView(loadedContent)
            } else if let errorMessage {
                chapterLoadErrorView(errorMessage).readerOpeningContentReady()
            } else if readerOpeningManaged {
                Color.clear
            } else {
                if let openingBook {
                    ReaderOpeningPage(book: openingBook, chapterTitle: effectiveChapter.title)
                } else {
                    chapterLoadingView
                }
            }
        }
        .background(ReaderTabChromeExitBridge(owner: chapterLoadingTabChromeOwner))
        .onAppear {
            appState.acquireTabChromeHidden(owner: chapterLoadingTabChromeOwner)
        }
        .onDisappear {
            appState.releaseTabChromeHidden(owner: chapterLoadingTabChromeOwner)
        }
        .overlay(alignment: .top) {
            if isCachingNext {
                Text("Caching adjacent chapters...")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassPanel(cornerRadius: 14, material: .thinMaterial, shadowOpacity: 0.08)
                    .padding(.top, 14)
            }
        }
        .task(id: effectiveChapter) {
            guard loadedChapter != effectiveChapter else { return }
            await load(force: content != nil)
        }
        .sheet(isPresented: $showBookDetailSheet) {
            NavigationStack {
                BookDetailView(book: detailSheetSearchBook)
            }
        }
    }

    private var cachedOpeningContent: ChapterContent? {
        appState.chapterContentCacheStore.content(sourceURL: sourceUrl, chapter: effectiveChapter,
            purifyRules: appState.purifyRuleStore.enabledPatterns)
    }

    private var detailSheetSearchBook: SearchBook {
        if let bookID, let shelfBook = appState.bookshelfStore.book(id: bookID) {
            return shelfBook.asSearchBook
        }
        let sourceName = appState.sourceStore.source(for: sourceUrl)?.bookSourceName ?? sourceUrl
        return SearchBook(
            name: effectiveChapter.title,
            author: nil,
            coverUrl: nil,
            bookUrl: effectiveChapter.bookUrl,
            sourceName: sourceName,
            sourceUrl: sourceUrl,
            mediaKind: resolvedChapterSource?.sourceKind
        )
    }

    private func load(force: Bool = false, ignoreCache: Bool = false) async {
        if force {
            // 换章时保留上一章正文，避免整屏 loading 和 ReaderView 重建。
            errorMessage = nil
            isUsingStaleCache = false
        }
        guard (content == nil || force), errorMessage == nil else { return }
        guard let source = resolvedChapterSource else {
            errorMessage = "找不到书源"
            return
        }
        if source.sourceKind != .text {
            return
        }
        let purifyRules = appState.purifyRuleStore.enabledPatterns
        let targetChapter = effectiveChapter
        if !ignoreCache, let cached = appState.chapterContentCacheStore.content(
            sourceURL: source.bookSourceUrl,
            chapter: targetChapter,
            purifyRules: purifyRules
        ) {
            content = cached
            loadedChapter = targetChapter
            isUsingStaleCache = false
            return
        }
        let engine = appState.engine
        let contentResult = await AsyncTimeout.run(seconds: 20) {
            await engine.getContent(source: source, chapter: targetChapter)
        } ?? .failure(.network("Content load timed out"))
        guard !Task.isCancelled, effectiveChapter == targetChapter else { return }
        switch contentResult {
        case .success(let loaded):
            appState.chapterContentCacheStore.save(loaded, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
            content = loaded
            loadedChapter = targetChapter
            isUsingStaleCache = false
        case .failure(let error):
            if let cached = appState.chapterContentCacheStore.staleContent(
                sourceURL: source.bookSourceUrl,
                chapter: targetChapter
            ) {
                content = cached
                loadedChapter = targetChapter
                isUsingStaleCache = true
            } else {
                errorMessage = error.displayMessage
            }
        }
    }

    /// Forward chapters first (the reading direction), then the same number
    /// behind the cursor. Already-cached chapters are skipped so the queue
    /// never duplicates a request.
    private func chaptersToCache(
        around chapter: BookChapter,
        source: BookSource,
        purifyRules: [String],
        count: Int
    ) -> [BookChapter] {
        guard count > 0 else { return [] }
        let forward = chapters
            .filter { $0.index > chapter.index }
            .sorted { $0.index < $1.index }
            .prefix(count)
        let backward = chapters
            .filter { $0.index < chapter.index }
            .sorted { $0.index > $1.index }
            .prefix(count)
        return (Array(forward) + Array(backward)).filter { candidate in
            !appState.chapterContentCacheStore.isCached(
                sourceURL: source.bookSourceUrl,
                chapter: candidate,
                purifyRules: purifyRules
            )
        }
    }

    private func readerView(_ loadedContent: ChapterContent) -> some View {
        ReaderView(
            bookID: bookID ?? "\(sourceUrl)|\(chapter.bookUrl)",
            content: loadedContent,
            chapterIndex: effectiveChapter.index,
            totalChapters: totalChapters,
            chapters: chapters,
            initialParagraphIndex: currentParagraphIndex ?? (effectiveChapter.index == chapter.index ? initialParagraphIndex : nil),
            statusMessage: isUsingStaleCache ? "网络加载失败，正在显示本地缓存副本" : nil,
            extraToolbarActions: extraToolbarActions,
            onRequestSourceSwitch: onRequestSourceSwitch,
            onRequestBookDetail: onRequestBookDetail ?? { showBookDetailSheet = true },
            onSelectChapter: { selected in
                showReaderChromeAfterChapterSelection = true
                currentChapter = selected
                currentParagraphIndex = nil
                errorMessage = nil
                isUsingStaleCache = false
            },
            onSelectChapterWithPosition: { selected, targetParagraph in
                showReaderChromeAfterChapterSelection = true
                currentChapter = selected
                currentParagraphIndex = targetParagraph
                errorMessage = nil
                isUsingStaleCache = false
            },
            onRefreshChapter: {
                Task { await load(force: true, ignoreCache: true) }
            },
            onCacheNextChapters: { cursorChapterIndex in
                Task { await cacheAdjacentChaptersFromReader(around: cursorChapterIndex) }
            },
            onSpeechFinished: {
                guard let next = chapters.first(where: { $0.index == effectiveChapter.index + 1 }) else { return }
                autoplaySpeechAfterHandoff = true
                currentChapter = next
                errorMessage = nil
                isUsingStaleCache = false
            },
            autoplaySpeechOnAppear: autoplaySpeechAfterHandoff,
            onSpeechAutoplayConsumed: { autoplaySpeechAfterHandoff = false },
            autoplayAutoScrollOnAppear: autoplayAutoScrollAfterHandoff,
            onAutoScrollAutoplayConsumed: { autoplayAutoScrollAfterHandoff = false },
            onAutoScrollFinished: {
                guard let next = chapters.first(where: { $0.index == effectiveChapter.index + 1 }) else { return }
                autoplayAutoScrollAfterHandoff = true
                currentChapter = next
                currentParagraphIndex = nil
                errorMessage = nil
                isUsingStaleCache = false
                if let bookID {
                    appState.bookshelfStore.updateReadingProgress(
                        bookID: bookID,
                        chapterIndex: next.index,
                        chapterTitle: next.title,
                        totalChapters: totalChapters ?? chapters.count
                    )
                }
            },
            initialOverlayVisible: showReaderChromeAfterChapterSelection,
            onPreviewPosition: onPreviewPosition,
            onRequestExit: onRequestExit
        )
        // 书级稳定身份：换章只更新 content，不再销毁 ReaderView + WKWebView。
        .id("reader-\(bookID ?? sourceUrl)")
    }

    private func cacheAdjacentChapters(around chapter: BookChapter, source: BookSource, purifyRules: [String]) async {
        let count = ReaderPreloadPolicy.clamp(preloadChapterCount)
        guard count > 0 else { return }
        let pending = chaptersToCache(around: chapter, source: source, purifyRules: purifyRules, count: count)
        let engine = appState.engine
        for next in pending {
            let result = await AsyncTimeout.run(seconds: 10) {
                await engine.getContent(source: source, chapter: next)
            } ?? .failure(.network("Cache timed out"))
            if case .success(let loaded) = result {
                appState.chapterContentCacheStore.save(
                    loaded,
                    sourceURL: source.bookSourceUrl,
                    purifyRules: purifyRules
                )
            }
        }
    }

    private var chapterLoadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            VStack(spacing: 6) {
                Text("正在加载正文")
                    .font(.headline)
                Text(effectiveChapter.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(AppTheme.pagePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .pageBackground()
    }

    private func cacheAdjacentChaptersFromReader(around cursorChapterIndex: Int) async {
        guard !isCachingNext else { return }
        guard let source = appState.sourceStore.source(for: sourceUrl) else { return }
        let target = chapters.first(where: { $0.index == cursorChapterIndex }) ?? effectiveChapter
        isCachingNext = true
        defer { isCachingNext = false }
        await cacheAdjacentChapters(around: target, source: source, purifyRules: appState.purifyRuleStore.enabledPatterns)
    }

    private func chapterLoadErrorView(_ message: String) -> some View {
        VStack(spacing: 14) {
            EmptyStateCard(systemImage: "xmark.octagon", title: "正文加载失败", message: message)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                UIPasteboard.general.string = chapterDiagnosticText()
            } label: {
                Label("复制精简诊断", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await load(force: true, ignoreCache: true) }
            } label: {
                Label("重试当前章节", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let onRequestSourceSwitch {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onRequestSourceSwitch()
                } label: {
                    Label("换源继续阅读", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(AppTheme.pagePadding)
        .pageBackground()
    }

    private func chapterDiagnosticText() -> String {
        // Rule URLs can embed headers and authentication; even path segments
        // may be signed. Keep the origin and chapter index, not raw errors.
        let chapterHost = SourceDiagnosticRedactor.originHost(effectiveChapter.url) ?? "未知"
        let sourceHost = SourceDiagnosticRedactor.originHost(sourceUrl) ?? "未知"
        return [
            "正文加载失败",
            "书源主机: \(sourceHost)",
            "正文主机: \(chapterHost)",
            "章节序号: \(effectiveChapter.index + 1)"
        ].joined(separator: "\n")
    }

    init(
        bookID: String? = nil,
        sourceUrl: String,
        chapter: BookChapter,
        totalChapters: Int? = nil,
        chapters: [BookChapter] = [],
        initialParagraphIndex: Int? = nil,
        openingBook: BookshelfBook? = nil,
        extraToolbarActions: @escaping () -> AnyView = { AnyView(EmptyView()) },
        onRequestSourceSwitch: (() -> Void)? = nil,
        onRequestBookDetail: (() -> Void)? = nil,
        onPreviewPosition: ((ReaderPreviewPosition) -> Void)? = nil,
        onRequestExit: (() -> Void)? = nil
    ) {
        self.bookID = bookID
        self.sourceUrl = sourceUrl
        self.chapter = chapter
        self.totalChapters = totalChapters
        self.chapters = chapters
        _initialParagraphIndex = State(initialValue: initialParagraphIndex)
        self.openingBook = openingBook
        self.extraToolbarActions = extraToolbarActions
        self.onRequestSourceSwitch = onRequestSourceSwitch
        self.onRequestBookDetail = onRequestBookDetail
        self.onPreviewPosition = onPreviewPosition
        self.onRequestExit = onRequestExit
    }
}

private struct BookDetailAllChaptersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let chapters: [BookChapter]
    @State private var selectedChapterForReading: BookChapter? = nil
    let book: SearchBook
    let bookID: String
    /// Local imports resolve through the bookshelf record because they have no
    /// book source to read chapters from.
    let localBook: BookshelfBook?
    let onPreviewPosition: (ReaderPreviewPosition) -> Void
    let onReaderReturn: () -> Void
    @Binding var addPrompt: Bool
    let addBook: () -> Void
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var isAscending = true
    @State private var tocFilterCache = ReaderTocFilterCache()

    private var filteredChapters: [BookChapter] {
        tocFilterCache.chapters(query: debouncedQuery, reversed: !isAscending, chapters: chapters)
    }

    var body: some View {
        let visibleChapters = filteredChapters
        return NavigationStack {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    TextField("筛选章节名或序号", text: $query)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    if !query.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            query = ""
                            debouncedQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(AppPressStyle())
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)
                .padding(.top, 6)

                List {
                    if visibleChapters.isEmpty {
                        Text("没有匹配章节")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(Array(visibleChapters.enumerated()), id: \.element.id) { index, chapter in
                            // One stable row per chapter lets List stay lazy even
                            // when volumes are present. Filtering is done once,
                            // not twice again for every row it inspects.
                            VStack(alignment: .leading, spacing: 8) {
                            if let volume = ChapterListPresenter.volumeHeader(at: index, in: visibleChapters) {
                                Text(volume)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                selectedChapterForReading = chapter
                            } label: {
                                HStack(spacing: 12) {
                                    Text("\(chapter.index + 1)")
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chapter.title)
                                            .font(.system(size: 15))
                                            .lineLimit(1)
                                        if let metadata = ChapterListPresenter.metadataLabel(chapter) {
                                            Text(metadata)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    if chapter.isVip {
                                        Text("VIP")
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(AppPressStyle())
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
                .navigationDestination(isPresented: Binding(
                    get: { selectedChapterForReading != nil },
                    set: { if !$0 { selectedChapterForReading = nil } }
                )) {
                    if let chapter = selectedChapterForReading {
                        if let shelfBook = localBook {
                            BookshelfReaderGatewayView(book: shelfBook, initialChapterIndex: chapter.index)
                        } else if let source = appState.sourceStore.source(for: book.sourceUrl)?.resolvingMediaKind(book.mediaKind), source.sourceKind == .comic {
                            ComicReaderView(bookID: bookID, bookTitle: book.name, source: source,
                                initialChapterIndex: chapter.index, chapters: chapters, engine: appState.engine,
                                onPreviewPosition: onPreviewPosition)
                        } else {
                            ChapterLoadingView(
                                bookID: bookID,
                                sourceUrl: book.sourceUrl,
                                chapter: chapter,
                                totalChapters: chapters.count,
                                chapters: chapters,
                                onPreviewPosition: onPreviewPosition
                            )
                        }
                    }
                }
            }
            .task(id: query) {
                if query.isEmpty {
                    debouncedQuery = ""
                    return
                }
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                debouncedQuery = query
            }
            .navigationTitle("完整目录 (\(chapters.count) 章)")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedChapterForReading != nil) { if !$0 { onReaderReturn() } }
            .modifier(ReaderPreviewShelfPrompt(isPresented: $addPrompt, addBook: addBook))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isAscending ? "倒序" : "正序") {
                        isAscending.toggle()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct ReaderPreviewShelfPrompt: ViewModifier {
    @Binding var isPresented: Bool
    let addBook: () -> Void

    func body(content: Content) -> some View {
        // A popover-style confirmation dialog can omit its cancel action.
        // Declining is a visible choice in the preview flow, not outside-tap only.
        content.alert("加入书架？", isPresented: $isPresented) {
            Button("加入书架", action: addBook)
            Button("暂不加入", role: .cancel) {}
        } message: {
            Text("加入书架并保留这次的阅读位置。")
        }
    }
}

