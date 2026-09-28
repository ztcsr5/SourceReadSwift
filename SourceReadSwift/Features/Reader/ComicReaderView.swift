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
    @Environment(\.dismiss) private var dismiss
    let bookID: String
    let bookTitle: String
    let source: BookSource
    let initialChapterIndex: Int
    let chapters: [BookChapter]
    let engine: SourceEngine

    @State private var currentChapterIndex: Int
    @State private var pages: [ComicPage] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var readingMode: ComicReadingMode = .vertical
    @State private var showChrome = true
    @State private var showChapterDrawer = false
    @State private var currentPageIndex: Int = 0

    init(
        bookID: String,
        bookTitle: String,
        source: BookSource,
        initialChapterIndex: Int,
        chapters: [BookChapter],
        engine: SourceEngine
    ) {
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.source = source
        self.initialChapterIndex = initialChapterIndex
        self.chapters = chapters
        self.engine = engine
        self._currentChapterIndex = State(initialValue: initialChapterIndex)
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
                        loadChapter(at: currentChapterIndex)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                mainContentView
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showChrome.toggle()
                        }
                    }
            }

            if showChrome {
                chromeOverlay
            }
        }
        .task {
            loadChapter(at: currentChapterIndex)
        }
        .sheet(isPresented: $showChapterDrawer) {
            chapterDrawerSheet
        }
        .statusBarHidden(!showChrome)
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
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(pages) { page in
                    ComicPageImageView(url: page.url, pageNumber: page.id + 1, totalPages: pages.count)
                }

                // Next chapter trigger card
                if currentChapterIndex + 1 < chapters.count {
                    Button {
                        loadChapter(at: currentChapterIndex + 1)
                    } label: {
                        HStack {
                            Text("下一话：\(chapters[currentChapterIndex + 1].title)")
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.vertical, 32)
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Text("全本完结")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.vertical, 32)
                }
            }
        }
    }

    private func horizontalPager(rtl: Bool) -> some View {
        TabView(selection: $currentPageIndex) {
            let displayedPages = rtl ? Array(pages.reversed()) : pages
            ForEach(displayedPages) { page in
                ComicPageImageView(url: page.url, pageNumber: page.id + 1, totalPages: pages.count)
                    .tag(page.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - Chrome Overlay

    private var chromeOverlay: some View {
        VStack {
            // Top Bar
            HStack(spacing: 16) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let chapter = currentChapter {
                        Text(chapter.title)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Reading Mode Picker Menu
                Menu {
                    ForEach(ComicReadingMode.allCases) { mode in
                        Button {
                            readingMode = mode
                        } label: {
                            HStack {
                                Label(mode.rawValue, systemImage: mode.systemImage)
                                if readingMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: readingMode.systemImage)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }

                // Chapter Drawer Button
                Button {
                    showChapterDrawer = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Circle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)

            Spacer()

            // Bottom Bar
            VStack(spacing: 12) {
                HStack(spacing: 20) {
                    Button {
                        if currentChapterIndex > 0 {
                            loadChapter(at: currentChapterIndex - 1)
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

                    if !pages.isEmpty {
                        Text("\(currentPageIndex + 1) / \(pages.count) P")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.7))
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
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
        .transition(.opacity)
    }

    private var chapterDrawerSheet: some View {
        NavigationStack {
            List {
                ForEach(chapters.indices, id: \.self) { idx in
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
            .navigationTitle("漫画目录 (\(chapters.count)话)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        showChapterDrawer = false
                    }
                }
            }
        }
    }

    // MARK: - Logic

    private func loadChapter(at index: Int) {
        guard chapters.indices.contains(index) else { return }
        currentChapterIndex = index
        let chapter = chapters[index]
        isLoading = true
        errorMessage = nil
        currentPageIndex = 0

        if !bookID.isEmpty {
            appState.bookshelfStore.updateReadingProgress(
                bookID: bookID,
                chapterIndex: index,
                chapterTitle: chapter.title,
                totalChapters: chapters.count
            )
        }

        Task {
            let result = await engine.getContent(source: source, chapter: chapter)
            await MainActor.run {
                self.isLoading = false
                switch result {
                case .success(let content):
                    let parsedPages = ComicContentParser.parsePages(from: content)
                    if parsedPages.isEmpty {
                        self.errorMessage = "未在当前章节解析到漫画图片"
                    } else {
                        self.pages = parsedPages
                    }
                case .failure(let error):
                    self.errorMessage = error.displayMessage
                }
            }
        }
    }
}

// MARK: - Comic Page Image with Pinch-to-Zoom

private struct ComicPageImageView: View {
    let url: String
    let pageNumber: Int
    let totalPages: Int

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            if let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                    case .failure:
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.largeTitle)
                                .foregroundStyle(.white.opacity(0.4))
                            Text("第 \(pageNumber) 页加载失败")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                        .background(Color.white.opacity(0.05))
                    case .empty:
                        ZStack {
                            Color.white.opacity(0.05)
                            ProgressView()
                                .tint(.white)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    @unknown default:
                        Color.clear
                    }
                }
            }
        }
        .scaleEffect(scale)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    scale = max(1.0, min(lastScale * value, 3.5))
                }
                .onEnded { _ in
                    lastScale = scale
                    if scale < 1.05 {
                        withAnimation {
                            scale = 1.0
                            lastScale = 1.0
                        }
                    }
                }
        )
        .onTapGesture(count: 2) {
            withAnimation(.spring()) {
                if scale > 1.2 {
                    scale = 1.0
                    lastScale = 1.0
                } else {
                    scale = 2.0
                    lastScale = 2.0
                }
            }
        }
    }
}
