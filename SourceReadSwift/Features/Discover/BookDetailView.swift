import SwiftUI
import UIKit

struct BookDetailView: View {
    @EnvironmentObject private var appState: AppState
    let initialBook: SearchBook
    var availableSources: [SearchBook] = []
    @State private var book: SearchBook
    @State private var detail: BookDetail?
    @State private var chapters: [BookChapter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didOpenReader = false
    @State private var hasPromptedAddAfterPreview = false
    @State private var showAddAfterPreviewPrompt = false
    @State private var isAscending = true
    @State private var showAllChapters = false
    @State private var showAudioPlayer = false
    @State private var showComicReader = false
    @State private var showVideoPlayer = false
    @State private var selectedChapterIndexForReader = 0

    private var sourceKind: BookSourceKind {
        if let source = appState.sourceStore.source(for: book.sourceUrl) {
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
        appState.chapterDownloadStore.record(bookID: book.id)
    }

    private var isDownloading: Bool {
        appState.chapterDownloadCoordinator.isRunning(bookID: book.id)
    }

    private var displayedChapters: [BookChapter] {
        Array((isAscending ? chapters : Array(chapters.reversed())).prefix(20))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SearchBookRow(
                    book: book,
                    onAdd: {
                        addCurrentBookToShelf()
                    },
                    isInBookshelf: appState.bookshelfStore.contains(book)
                )
                    .podcastCard()

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
                    .frame(maxWidth: .infinity, minHeight: 220)
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
                            // Local imports have no book source, so the batch cache
                            // card could only ever render dead buttons; keep it for
                            // source-backed books.
                            if !chapters.isEmpty, !book.sourceUrl.hasPrefix("local://") {
                                downloadSection
                            }
                        }
                        chapterList
                    }
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
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
                    .disabled(chapters.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("书籍操作")
            }
        }
        .task {
            await load()
        }
        .sheet(isPresented: $showAllChapters) {
            BookDetailAllChaptersView(
                chapters: chapters,
                book: book,
                bookID: readerBookID,
                localBook: localShelfBook
            )
        }
        .sheet(isPresented: $showAudioPlayer) {
            AudioBookPlayerView()
        }
        .fullScreenCover(isPresented: $showComicReader) {
            if let source = appState.sourceStore.source(for: book.sourceUrl) {
                ComicReaderView(
                    bookID: appState.bookshelfStore.contains(book) ? book.id : "\(book.sourceUrl)|\(book.bookUrl)",
                    bookTitle: book.name,
                    source: source,
                    initialChapterIndex: selectedChapterIndexForReader,
                    chapters: chapters,
                    engine: appState.engine
                )
            }
        }
        .fullScreenCover(isPresented: $showVideoPlayer) {
            if let source = appState.sourceStore.source(for: book.sourceUrl) {
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
        .onAppear {
            promptToAddAfterPreviewIfNeeded()
        }
        .confirmationDialog(
            "加入书架？",
            isPresented: $showAddAfterPreviewPrompt,
            titleVisibility: .visible
        ) {
            Button("加入书架") {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                addCurrentBookToShelf()
            }
            Button("暂不加入", role: .cancel) {}
        } message: {
            Text("如果这本书符合预期，可以加入书架，后续会记录阅读进度和更新状态。")
        }
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
            .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.name)
                .font(.title.bold())
            Text(detail.author ?? "作者未知")
                .font(.headline)
                .foregroundStyle(.secondary)
            if let intro = detail.intro, !intro.isEmpty {
                Text(intro)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineSpacing(5)
            }
            let metadata = detailMetadata(detail)
            if !metadata.isEmpty {
                HStack(spacing: 8) {
                    ForEach(metadata.indices, id: \.self) { index in
                        Text(metadata[index])
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppTheme.accent.opacity(0.12), in: Capsule())
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            if let latest = detail.latestChapter {
                Text("最新：\(latest)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .podcastCard()
    }

    private func detailMetadata(_ detail: BookDetail) -> [String] {
        var items: [String] = []
        if let kind = detail.kind?.nilIfEmpty {
            items.append(kind)
        }
        if let status = detail.status?.nilIfEmpty {
            items.append(status)
        }
        if let wordCount = detail.wordCount?.nilIfEmpty {
            items.append("字数 \(wordCount)")
        }
        if let updateTime = detail.updateTime?.nilIfEmpty {
            items.append("更新 \(updateTime)")
        }
        return items
    }

    private var audioBookActionCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if let source = appState.sourceStore.source(for: book.sourceUrl) {
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
            selectedChapterIndexForReader = 0
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("目录")
                    .font(.title2.bold())
                Spacer()
                Text("\(chapters.count) 章")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(displayedChapters.indices, id: \.self) { index in
                    let chapter = displayedChapters[index]
                    if let volume = ChapterListPresenter.volumeHeader(at: index, in: displayedChapters) {
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
                            if let source = appState.sourceStore.source(for: book.sourceUrl) {
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
                        .buttonStyle(.plain)

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
                        .buttonStyle(.plain)

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
                        .buttonStyle(.plain)

                    case .text:
                        // Local imports have no book source, and ChapterLoadingView
                        // bails out with 「找不到书源」 for them. They open through the
                        // same local reader route the shelf uses instead.
                        textChapterLink(chapter)
                            .simultaneousGesture(TapGesture().onEnded {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                didOpenReader = true
                            })
                    }

                    if index < displayedChapters.count - 1 {
                        Divider()
                            .padding(.leading, 14)
                    }
                }
            }
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))

            if chapters.count > displayedChapters.count {
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

    @ViewBuilder
    private func textChapterLink(_ chapter: BookChapter) -> some View {
        if let shelfBook = localShelfBook {
            NavigationLink {
                BookshelfReaderGatewayView(book: shelfBook, initialChapterIndex: chapter.index)
            } label: {
                textChapterRowLabel(chapter)
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink {
                ChapterLoadingView(
                    bookID: readerBookID,
                    sourceUrl: book.sourceUrl,
                    chapter: chapter,
                    totalChapters: chapters.count,
                    chapters: chapters
                )
            } label: {
                textChapterRowLabel(chapter)
            }
            .buttonStyle(.plain)
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

    private func load() async {
        guard detail == nil, !isLoading else { return }
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

        guard let source = appState.sourceStore.source(for: book.sourceUrl) else {
            errorMessage = "找不到书源：\(book.sourceName)"
            return
        }

        isLoading = true
        defer { isLoading = false }

        let engine = appState.engine
        let selectedBook = book
        let detailResult = await AsyncTimeout.run(seconds: 20) {
            await engine.getBookDetail(source: source, book: selectedBook)
        } ?? .failure(.network("Detail load timed out"))
        switch detailResult {
        case .success(let loadedDetail):
            detail = loadedDetail
            let chapterResult = await AsyncTimeout.run(seconds: 20) {
                await engine.getChapterList(source: source, book: loadedDetail)
            } ?? .failure(.network("Chapter list timed out"))
            switch chapterResult {
            case .success(let loadedChapters):
                chapters = loadedChapters
                if appState.bookshelfStore.contains(book) {
                    appState.bookshelfStore.updateDetails(
                        bookID: book.id,
                        latestChapterTitle: loadedDetail.latestChapter,
                        intro: loadedDetail.intro,
                        totalChapters: loadedChapters.count
                    )
                }
            case .failure(let error):
                errorMessage = "目录加载失败：\(error.displayMessage)"
            }
        case .failure(let error):
            errorMessage = error.displayMessage
        }
    }

    private func reload() async {
        detail = nil
        chapters = []
        errorMessage = nil
        await load()
    }

    private func markAsRead() {
        guard !chapters.isEmpty else { return }
        if !appState.bookshelfStore.contains(book) {
            appState.bookshelfStore.addOrUpdate(book)
        }
        appState.bookshelfStore.updateReadingProgress(
            bookID: readerBookID,
            chapterIndex: max(chapters.count - 1, 0),
            chapterTitle: chapters.last?.title,
            totalChapters: chapters.count
        )
    }

    private var downloadLabel: String {
        if isDownloading { return "停止缓存" }
        guard let record = downloadRecord else { return "缓存全本章节" }
        switch record.status {
        case .completed: return "全本已缓存"
        case .paused: return "继续缓存 \(record.completedCount)/\(record.chapterCount)"
        case .failed: return "重试缓存（失败 \(record.failedCount)）"
        case .cancelled, .queued, .running: return "继续缓存 \(record.completedCount)/\(record.chapterCount)"
        }
    }

    private func toggleDownload() {
        if isDownloading {
            appState.chapterDownloadCoordinator.cancel(bookID: book.id)
            return
        }
        guard !chapters.isEmpty,
              let source = appState.sourceStore.source(for: book.sourceUrl) else { return }
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
        appState.bookshelfStore.addOrUpdate(book)
        if let detail {
            appState.bookshelfStore.updateDetails(
                bookID: book.id,
                latestChapterTitle: detail.latestChapter,
                intro: detail.intro,
                totalChapters: chapters.count
            )
        }
    }

    private func promptToAddAfterPreviewIfNeeded() {
        guard didOpenReader else { return }
        didOpenReader = false
        guard !hasPromptedAddAfterPreview,
              !appState.bookshelfStore.contains(book) else { return }
        hasPromptedAddAfterPreview = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showAddAfterPreviewPrompt = true
        }
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

    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(AppTheme.accent)
                Text("批量离线缓存")
                    .font(.headline)
                Spacer()
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                    Button("停止") {
                        appState.chapterDownloadCoordinator.cancel(bookID: book.id)
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }

            if let record = downloadRecord {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(record.completedCount), total: Double(max(record.chapterCount, 1)))
                        .tint(AppTheme.accent)
                    HStack {
                        Text("已缓存 \(record.completedCount)/\(record.chapterCount) 章")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if record.failedCount > 0 {
                            Text("(\(record.failedCount) 章失败)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Spacer()
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    downloadChapters(limit: 50)
                } label: {
                    Label("缓存后50章", systemImage: "arrow.down.to.line")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(chapters.isEmpty || isDownloading)

                Button {
                    downloadChapters(limit: nil)
                } label: {
                    Label("全本缓存", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .disabled(chapters.isEmpty || isDownloading)
            }
        }
        .podcastCard()
    }

    private func downloadChapters(limit: Int?) {
        guard !chapters.isEmpty,
              let source = appState.sourceStore.source(for: book.sourceUrl) else { return }
        let targets: [BookChapter]
        if let limit {
            targets = Array(chapters.prefix(limit))
        } else {
            targets = chapters
        }
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
    let bookID: String?
    let sourceUrl: String
    let chapter: BookChapter
    var totalChapters: Int? = nil
    var chapters: [BookChapter] = []
    var initialParagraphIndex: Int? = nil
    var extraToolbarActions: () -> AnyView = { AnyView(EmptyView()) }
    var onRequestSourceSwitch: (() -> Void)?
    @State private var content: ChapterContent?
    @State private var currentChapter: BookChapter?
    @State private var currentParagraphIndex: Int? = nil
    @State private var errorMessage: String?
    @State private var isUsingStaleCache = false
    @State private var isCachingNext = false
    @State private var autoplaySpeechAfterHandoff = false
    @State private var autoplayAutoScrollAfterHandoff = false
    @State private var showReaderChromeAfterChapterSelection = false
    @AppStorage("reader.preloadChapterCount") private var preloadChapterCount = ReaderPreloadPolicy.defaultCount

    private var effectiveChapter: BookChapter {
        currentChapter ?? chapter
    }

    var body: some View {
        Group {
            if let loadedContent = content {
                readerView(loadedContent)
            } else if let errorMessage {
                chapterLoadErrorView(errorMessage)
            } else {
                chapterLoadingView
            }
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
        .task {
            await load()
        }
        .onChange(of: currentChapter) { _ in
            Task {
                await load(force: true)
            }
        }
    }

    private func load(force: Bool = false, ignoreCache: Bool = false) async {
        if force {
            content = nil
            errorMessage = nil
            isUsingStaleCache = false
        }
        guard content == nil, errorMessage == nil else { return }
        guard let source = appState.sourceStore.source(for: sourceUrl) else {
            errorMessage = "找不到书源"
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
            isUsingStaleCache = false
            return
        }
        let engine = appState.engine
        let contentResult = await AsyncTimeout.run(seconds: 20) {
            await engine.getContent(source: source, chapter: targetChapter)
        } ?? .failure(.network("Content load timed out"))
        switch contentResult {
        case .success(let loaded):
            appState.chapterContentCacheStore.save(loaded, sourceURL: source.bookSourceUrl, purifyRules: purifyRules)
            content = loaded
            isUsingStaleCache = false
        case .failure(let error):
            if let cached = appState.chapterContentCacheStore.staleContent(
                sourceURL: source.bookSourceUrl,
                chapter: targetChapter
            ) {
                content = cached
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
            onRequestBookDetail: { dismiss() },
            onSelectChapter: { selected in
                showReaderChromeAfterChapterSelection = true
                currentChapter = selected
                currentParagraphIndex = nil
                content = nil
                errorMessage = nil
                isUsingStaleCache = false
            },
            onSelectChapterWithPosition: { selected, targetParagraph in
                showReaderChromeAfterChapterSelection = true
                currentChapter = selected
                currentParagraphIndex = targetParagraph
                content = nil
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
                content = nil
                errorMessage = nil
                isUsingStaleCache = false
            },
            autoplaySpeechOnAppear: autoplaySpeechAfterHandoff,
            onSpeechAutoplayConsumed: { autoplaySpeechAfterHandoff = false },
            autoplayAutoScrollOnAppear: autoplayAutoScrollAfterHandoff,
            onAutoScrollAutoplayConsumed: { autoplayAutoScrollAfterHandoff = false },
            onAutoScrollFinished: {
                autoplayAutoScrollAfterHandoff = true
            },
            initialOverlayVisible: showReaderChromeAfterChapterSelection
        )
        .id("reader-\(effectiveChapter.url)")
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
                UIPasteboard.general.string = chapterDiagnosticText(message)
            } label: {
                Label("Copy diagnostics", systemImage: "doc.on.doc")
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

    private func chapterDiagnosticText(_ message: String) -> String {
        [
            "Chapter load failed",
            "sourceUrl: \(sourceUrl)",
            "bookUrl: \(effectiveChapter.bookUrl)",
            "chapterIndex: \(effectiveChapter.index)",
            "chapterTitle: \(effectiveChapter.title)",
            "chapterUrl: \(effectiveChapter.url)",
            "message: \(message)"
        ].joined(separator: "\n")
    }

    init(
        bookID: String? = nil,
        sourceUrl: String,
        chapter: BookChapter,
        totalChapters: Int? = nil,
        chapters: [BookChapter] = [],
        initialParagraphIndex: Int? = nil,
        extraToolbarActions: @escaping () -> AnyView = { AnyView(EmptyView()) },
        onRequestSourceSwitch: (() -> Void)? = nil
    ) {
        self.bookID = bookID
        self.sourceUrl = sourceUrl
        self.chapter = chapter
        self.totalChapters = totalChapters
        self.chapters = chapters
        self.initialParagraphIndex = initialParagraphIndex
        self.extraToolbarActions = extraToolbarActions
        self.onRequestSourceSwitch = onRequestSourceSwitch
    }
}

private struct BookDetailAllChaptersView: View {
    @Environment(\.dismiss) private var dismiss
    let chapters: [BookChapter]
    let book: SearchBook
    let bookID: String
    /// Local imports resolve through the bookshelf record because they have no
    /// book source to read chapters from.
    let localBook: BookshelfBook?
    @State private var query = ""
    @State private var debouncedQuery = ""
    @State private var isAscending = true

    private var filteredChapters: [BookChapter] {
        let q = debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = isAscending ? chapters : Array(chapters.reversed())
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(q) || "\($0.index + 1)".contains(q)
        }
    }

    var body: some View {
        NavigationStack {
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
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal)
                .padding(.top, 6)

                List {
                    if filteredChapters.isEmpty {
                        Text("没有匹配章节")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredChapters.indices, id: \.self) { index in
                            let chapter = filteredChapters[index]
                            if let volume = ChapterListPresenter.volumeHeader(at: index, in: filteredChapters) {
                                Text(volume)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.secondary)
                            }
                            NavigationLink {
                                if let shelfBook = localBook {
                                    BookshelfReaderGatewayView(book: shelfBook, initialChapterIndex: chapter.index)
                                } else {
                                    ChapterLoadingView(
                                        bookID: bookID,
                                        sourceUrl: book.sourceUrl,
                                        chapter: chapter,
                                        totalChapters: chapters.count,
                                        chapters: chapters
                                    )
                                }
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
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDismissesKeyboard(.interactively)
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
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(isAscending ? "倒序" : "正序") {
                        withAnimation { isAscending.toggle() }
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

