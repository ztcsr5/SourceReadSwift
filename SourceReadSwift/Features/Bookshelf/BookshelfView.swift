import SwiftUI
import UniformTypeIdentifiers

struct BookshelfView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFileImporter = false
    @State private var importMessage: String?
    @State private var isRefreshingBooks = false
    @State private var isImportingBook = false
    @State private var selectedBookForDetail: BookshelfBook?
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @AppStorage("bookshelf.isGridMode") private var isGridMode = true
    @State private var selectedMainGroup: String? = nil

    private var recentBooks: [BookshelfBook] {
        appState.bookshelfStore.recentBooks
    }

    private var updatedBooks: [BookshelfBook] {
        appState.bookshelfStore.updatedBooks
    }

    private var allBooks: [BookshelfBook] {
        appState.bookshelfStore.books
    }

    private var displayedShelfBooks: [BookshelfBook] {
        if let selectedMainGroup {
            return allBooks.filter { $0.groupName == selectedMainGroup }
        }
        return allBooks
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 30) {
                    readingSection
                    shelfSection
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 22)
            }
            .refreshable {
                await refreshBookshelf()
            }
            .background(bookshelfBackdrop)
            // Native large-title navigation gives the bounded collapse shown
            // in the reference: large at the top, compact and centered after
            // scrolling, rather than letting a custom title drift forever.
            .navigationTitle("主页")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !allBooks.isEmpty {
                        NavigationLink {
                            BookshelfCollectionView(title: "书架管理", books: allBooks, startsManaging: true)
                        } label: {
                            Label("管理", systemImage: "checklist")
                                .font(.system(size: 15, weight: .semibold))
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showFileImporter = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                    }
                    .accessibilityLabel("导入本地书籍")
                }
            }
            .alert("本地导入", isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(importMessage ?? "")
            }
            .sheet(isPresented: $showFileImporter) {
                UniversalDocumentPicker(
                    contentTypes: [
                        .plainText,
                        .text,
                        .data,
                        .content,
                        .item,
                        UTType(importedAs: "com.edc21.sourceread.source-json"),
                        UTType(filenameExtension: "txt") ?? .plainText,
                        UTType(filenameExtension: "text") ?? .text,
                        UTType(filenameExtension: "epub") ?? UTType(importedAs: "org.idpf.epub-container")
                    ],
                    onPick: { urls in
                        showFileImporter = false
                        importLocalBook(.success(urls))
                    },
                    onCancel: { showFileImporter = false }
                )
                .ignoresSafeArea()
            }
            .sheet(item: $selectedBookForDetail) { book in
                NavigationStack {
                    BookDetailView(book: book.asSearchBook)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    selectedBookForDetail = nil
                                }
                            }
                        }
                }
            }
            .overlay {
                if isImportingBook {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.3)
                                .tint(.white)
                            Text("正在智能分章与构建目录...")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .cornerRadius(18)
                        .shadow(color: .black.opacity(0.15), radius: 12)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
    }

    private var bookshelfBackdrop: some View {
        _ = themeModeRawValue
        return ZStack {
            AppTheme.background
            LinearGradient(
                colors: [
                    AppTheme.accent.opacity(colorScheme == .dark ? 0.16 : 0.08),
                    Color.clear,
                    Color.black.opacity(colorScheme == .dark ? 0.18 : 0.03)
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.03 : 0.45),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 40,
                endRadius: 420
            )
        }
        .ignoresSafeArea()
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            collectionHeader(title: "正在阅读", books: recentBooks)
            if recentBooks.isEmpty {
                emptyImportCard
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(recentBooks.prefix(10)) { book in
                            heroCard(book)
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.vertical, 4)
                }
                .padding(.horizontal, -AppTheme.pagePadding)
            }
        }
    }

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                collectionHeader(title: "最新更新", books: updatedBooks)
                if isRefreshingBooks {
                    ProgressView()
                        .controlSize(.small)
                } else if !allBooks.isEmpty {
                    Button {
                        Task { await refreshBookshelf() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("检查书籍更新")
                }
            }
            if updatedBooks.isEmpty {
                compactEmptyState(
                    icon: "sparkles",
                    title: "暂无更新",
                    message: allBooks.isEmpty ? "导入书籍后，更新会显示在这里" : "点击刷新按钮检查书籍更新"
                )
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(updatedBooks) { book in
                        updateRow(book)
                    }
                }
            }
        }
    }

    private var shelfSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            shelfHeader

            if !appState.bookshelfStore.groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        mainGroupChip("全部", isSelected: selectedMainGroup == nil) {
                            selectedMainGroup = nil
                        }
                        ForEach(appState.bookshelfStore.groups) { group in
                            mainGroupChip(group.name, isSelected: selectedMainGroup == group.name) {
                                selectedMainGroup = group.name
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 2)
                }
            }

            if allBooks.isEmpty {
                compactEmptyState(icon: "books.vertical", title: "书架还是空的", message: "支持 TXT、EPUB 与在线书源书籍")
            } else if displayedShelfBooks.isEmpty {
                compactEmptyState(icon: "folder", title: "该分组暂无书籍", message: "可在“管理”中长按书籍分配至此分组")
            } else if isGridMode {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 18
                ) {
                    ForEach(displayedShelfBooks) { book in
                        bookshelfGridCard(book)
                    }
                }
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(displayedShelfBooks) { book in
                        bookshelfRow(book)
                    }
                }
            }
        }
    }

    private var shelfHeader: some View {
        HStack(spacing: 12) {
            NavigationLink {
                BookshelfCollectionView(title: "书架", books: allBooks)
            } label: {
                HStack(spacing: 7) {
                    Text("书架")
                        .font(.system(size: 22, weight: .bold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if !allBooks.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        isGridMode.toggle()
                    }
                } label: {
                    Image(systemName: isGridMode ? "rectangle.grid.1x2" : "square.grid.2x2")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isGridMode ? "切换为列表视图" : "切换为网格视图")
            }
        }
    }

    private func mainGroupChip(_ name: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            Text(name)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? AppTheme.accent : AppTheme.card, in: Capsule())
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .overlay {
                    if !isSelected {
                        Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func collectionHeader(title: String, books: [BookshelfBook]) -> some View {
        NavigationLink {
            BookshelfCollectionView(title: title, books: books)
        } label: {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyImportCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showFileImporter = true
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.accent.opacity(0.14))
                    Image(systemName: "book.badge.plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 5) {
                    Text("导入第一本书")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("从文件中选择 TXT 或 EPUB，立即开始阅读")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .glassPanel(cornerRadius: 22, material: .thinMaterial, shadowOpacity: 0.08)
        }
        .buttonStyle(.plain)
    }

    private func compactEmptyState(icon: String, title: String, message: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .glassPanel(cornerRadius: 18, material: .thinMaterial, shadowOpacity: 0.07)
    }

    private func importLocalBook(_ result: Result<[URL], Error>) {
        guard !isImportingBook else { return }
        isImportingBook = true
        Task {
            defer {
                Task { @MainActor in
                    isImportingBook = false
                }
            }
            do {
                guard let url = try result.get().first else {
                    await MainActor.run {
                        HapticFeedback.error()
                        importMessage = "导入失败：没有选择文件。"
                    }
                    return
                }
                let localURL = try PickedDocumentAccess.copiedURL(from: url)
                let parsed: LocalTextBook = try await Task.detached(priority: .userInitiated) {
                    if localURL.pathExtension.localizedCaseInsensitiveCompare("epub") == .orderedSame {
                        return try LocalEPUBBookParser().parse(fileURL: localURL)
                    } else {
                        let data = try Data(contentsOf: localURL)
                        return LocalTxtSmartDivider().divide(data: data, fileName: localURL.lastPathComponent)
                    }
                }.value

                await MainActor.run {
                    appState.bookshelfStore.addLocalTextBook(parsed)
                    HapticFeedback.success()
                    importMessage = "已导入《\(parsed.title)》，共 \(parsed.chapters.count) 章、\(parsed.paragraphs.count) 段。"
                }
            } catch {
                await MainActor.run {
                    HapticFeedback.error()
                    importMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func refreshBookshelf() async {
        guard !isRefreshingBooks else { return }
        isRefreshingBooks = true
        defer { isRefreshingBooks = false }

        var refreshed = 0
        var failed = 0
        let books = appState.bookshelfStore.books
        let engine = appState.engine
        let candidates: [BookshelfRefreshCandidate] = books.compactMap { book in
            guard !book.sourceURL.hasPrefix("local://") else { return nil }
            guard let source = appState.sourceStore.source(for: book.sourceURL), source.enabled else {
                failed += 1
                return nil
            }
            let searchBook = SearchBook(
                name: book.title,
                author: book.author,
                coverUrl: book.coverURL,
                bookUrl: book.bookURL,
                sourceName: book.sourceName,
                sourceUrl: book.sourceURL,
                intro: book.intro
            )
            return BookshelfRefreshCandidate(bookID: book.id, source: source, book: searchBook)
        }

        // Refresh results arrive in bounded parallel batches. Keep the UI
        // reactive, but commit the bookshelf JSON once for the whole refresh
        // instead of encoding it after every completed book.
        appState.bookshelfStore.beginBatchUpdates()
        defer { appState.bookshelfStore.endBatchUpdates() }

        for batch in candidates.chunked(into: 4) {
            guard !Task.isCancelled else { break }
            await withTaskGroup(of: BookshelfRefreshResult.self) { group in
                for candidate in batch {
                    group.addTask {
                        let detailResult = await AsyncTimeout.run(seconds: 12) {
                            await engine.getBookDetail(source: candidate.source, book: candidate.book)
                        } ?? .failure(.network("Refresh timed out"))
                        switch detailResult {
                        case .success(let detail):
                            let chapterResult = await AsyncTimeout.run(seconds: 12) {
                                await engine.getChapterList(source: candidate.source, book: detail)
                            } ?? .failure(.network("Chapter refresh timed out"))
                            switch chapterResult {
                            case .success(let chapters):
                                return .success(
                                    bookID: candidate.bookID,
                                    latestChapterTitle: detail.latestChapter ?? chapters.last?.title,
                                    intro: detail.intro,
                                    totalChapters: chapters.count
                                )
                            case .failure(let error):
                                return .failure(bookID: candidate.bookID, message: error.displayMessage)
                            }
                        case .failure(let error):
                            return .failure(bookID: candidate.bookID, message: error.displayMessage)
                        }
                    }
                }

                for await result in group {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        break
                    }
                    switch result {
                    case .success(let bookID, let latestChapterTitle, let intro, let totalChapters):
                        appState.bookshelfStore.updateDetails(
                            bookID: bookID,
                            latestChapterTitle: latestChapterTitle,
                            intro: intro,
                            totalChapters: totalChapters
                        )
                        refreshed += 1
                    case .failure(let bookID, let message):
                        appState.bookshelfStore.markRefreshFailure(bookID: bookID, message: message)
                        failed += 1
                    }
                }
            }
        }

        if refreshed > 0 {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func heroCard(_ book: BookshelfBook) -> some View {
        NavigationLink {
            BookshelfReaderGatewayView(book: book)
        } label: {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    AsyncBookCover(urlString: book.coverURL, width: 78, height: 108)
                        .overlay(alignment: .topTrailing) {
                            if book.hasUpdates {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 12, height: 12)
                                    .overlay {
                                        Circle().stroke(Color.white, lineWidth: 1.5)
                                    }
                                    .offset(x: 4, y: -4)
                                    .shadow(color: .red.opacity(0.6), radius: 4)
                            }
                        }
                        .shadow(color: .black.opacity(0.28), radius: 16, x: 0, y: 10)

                    VStack(alignment: .leading, spacing: 7) {
                        Text(book.lastReadAt == nil ? "待开始" : "已读 \(Int(book.readingProgress * 100))%")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))

                        Text(book.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Text(book.author)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 14)

                HStack {
                    Label("继续阅读", systemImage: "book.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white)
                        .foregroundStyle(.black)
                        .clipShape(Capsule())
                    Spacer()
                    Image(systemName: "ellipsis")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .padding(20)
            .frame(width: 312, height: 246, alignment: .topLeading)
            .background(
                heroGradient(for: book)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.32 : 0.13), radius: 22, x: 0, y: 14)
            .padding(.vertical, 6)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .contextMenu {
            Button {
                selectedBookForDetail = book
            } label: {
                Label("书籍详情", systemImage: "info.circle")
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                appState.bookshelfStore.togglePin(bookID: book.id)
            } label: {
                Label(book.isPinned ? "取消置顶" : "置顶书籍", systemImage: book.isPinned ? "pin.slash" : "pin")
            }
            Button("从书架删除", role: .destructive) {
                appState.bookshelfStore.remove(bookID: book.id)
            }
        }
    }

    private func heroGradient(for book: BookshelfBook) -> LinearGradient {
        let palettes: [[Color]] = [
            [Color(red: 0.10, green: 0.16, blue: 0.09), Color(red: 0.18, green: 0.24, blue: 0.14)],
            [Color(red: 0.18, green: 0.14, blue: 0.12), Color(red: 0.30, green: 0.25, blue: 0.21)],
            [Color(red: 0.16, green: 0.14, blue: 0.28), Color(red: 0.28, green: 0.22, blue: 0.44)]
        ]
        let index = Int(book.id.hashValue.magnitude % UInt(palettes.count))
        return LinearGradient(colors: palettes[index], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func updateRow(_ book: BookshelfBook) -> some View {
        NavigationLink {
            BookshelfReaderGatewayView(book: book)
        } label: {
            HStack(spacing: 14) {
                AsyncBookCover(urlString: book.coverURL, width: 70, height: 100)

                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let latest = book.latestChapterTitle {
                        Text("更新到 \(latest)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(12)
            .glassPanel(cornerRadius: 18, material: .thinMaterial, shadowOpacity: 0.08)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            appState.bookshelfStore.markUpdatesSeen(bookID: book.id)
        })
    }

    private func bookshelfRow(_ book: BookshelfBook) -> some View {
        NavigationLink {
            BookshelfReaderGatewayView(book: book)
        } label: {
            HStack(spacing: 14) {
                AsyncBookCover(urlString: book.coverURL, width: 52, height: 72)
                    .overlay(alignment: .topLeading) {
                        if book.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(AppTheme.accent, in: Circle())
                                .offset(x: -2, y: -2)
                                .shadow(radius: 2)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if book.hasUpdates {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 10, height: 10)
                                .overlay {
                                    Circle().stroke(Color.white, lineWidth: 1.2)
                                }
                                .offset(x: 3, y: -3)
                                .shadow(color: .red.opacity(0.5), radius: 3)
                        }
                    }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 5) {
                        if book.isPinned {
                            Text("置顶")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text(book.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let current = book.currentChapterTitle {
                        Text("读到：\(current)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassPanel(cornerRadius: 16, material: .thinMaterial, shadowOpacity: 0.06)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .swipeActions(edge: .leading) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                appState.bookshelfStore.togglePin(bookID: book.id)
            } label: {
                Label(book.isPinned ? "取消置顶" : "置顶", systemImage: book.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) {
                appState.bookshelfStore.remove(bookID: book.id)
            }
        }
        .contextMenu {
            Button {
                selectedBookForDetail = book
            } label: {
                Label("书籍详情", systemImage: "info.circle")
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                appState.bookshelfStore.togglePin(bookID: book.id)
            } label: {
                Label(book.isPinned ? "取消置顶" : "置顶书籍", systemImage: book.isPinned ? "pin.slash" : "pin")
            }
            if !appState.bookshelfStore.groups.isEmpty {
                Menu("移动到分组") {
                    Button("移出分组") {
                        appState.bookshelfStore.moveBooks(bookIDs: [book.id], toGroupName: nil)
                    }
                    ForEach(appState.bookshelfStore.groups) { group in
                        Button(group.name) {
                            appState.bookshelfStore.moveBooks(bookIDs: [book.id], toGroupName: group.name)
                        }
                    }
                }
            }
            Button("从书架删除", role: .destructive) {
                appState.bookshelfStore.remove(bookID: book.id)
            }
        }
    }

    private func bookshelfGridCard(_ book: BookshelfBook) -> some View {
        NavigationLink {
            BookshelfReaderGatewayView(book: book)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    AsyncBookCover(urlString: book.coverURL, width: nil, height: 145)
                        .frame(maxWidth: .infinity)
                        .frame(height: 145)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        }
                        .overlay(alignment: .topLeading) {
                            if book.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(AppTheme.accent, in: Circle())
                                    .offset(x: 4, y: 4)
                                    .shadow(radius: 2)
                            }
                        }
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.12), radius: 6, x: 0, y: 4)

                    if book.hasUpdates {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle().stroke(Color.white, lineWidth: 1.5)
                            }
                            .offset(x: 2, y: -2)
                            .shadow(color: .red.opacity(0.6), radius: 3)
                    }

                    if let current = book.currentChapterTitle {
                        VStack {
                            Spacer()
                            HStack {
                                Text(current)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(.ultraThinMaterial.opacity(0.95))
                                    .background(Color.black.opacity(0.45))
                                    .clipShape(Capsule())
                                Spacer()
                            }
                            .padding(5)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(height: 34, alignment: .topLeading)

                    Text(book.author.isEmpty ? (book.groupName ?? "未知作者") : book.author)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(PressableScaleButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .contextMenu {
            Button {
                selectedBookForDetail = book
            } label: {
                Label("书籍详情", systemImage: "info.circle")
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                appState.bookshelfStore.togglePin(bookID: book.id)
            } label: {
                Label(book.isPinned ? "取消置顶" : "置顶书籍", systemImage: book.isPinned ? "pin.slash" : "pin")
            }
            if !appState.bookshelfStore.groups.isEmpty {
                Menu("移动到分组") {
                    Button("移出分组") {
                        appState.bookshelfStore.moveBooks(bookIDs: [book.id], toGroupName: nil)
                    }
                    ForEach(appState.bookshelfStore.groups) { group in
                        Button(group.name) {
                            appState.bookshelfStore.moveBooks(bookIDs: [book.id], toGroupName: group.name)
                        }
                    }
                }
            }
            Button("从书架删除", role: .destructive) {
                appState.bookshelfStore.remove(bookID: book.id)
            }
        }
    }
}

private struct BookshelfRefreshCandidate: Sendable {
    let bookID: String
    let source: BookSource
    let book: SearchBook
}

private enum BookshelfRefreshResult: Sendable {
    case success(bookID: String, latestChapterTitle: String?, intro: String?, totalChapters: Int)
    case failure(bookID: String, message: String)
}

private struct BookshelfCollectionView: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let books: [BookshelfBook]
    @State private var selectedGroupName: String?
    @State private var showGroupEditor = false
    @State private var groupName = ""
    @State private var isManaging = false
    @State private var selectedBookIDs: Set<String> = []
    @State private var confirmBatchDelete = false
    @State private var selectedBookForDetail: BookshelfBook?
    @State private var searchKeyword = ""
    @State private var debouncedSearchKeyword = ""

    init(title: String, books: [BookshelfBook], startsManaging: Bool = false) {
        self.title = title
        self.books = books
        _isManaging = State(initialValue: startsManaging)
    }

    /// The collection receives an initial projection from the root page, but
    /// mutations (batch delete, grouping, source refresh) happen in the shared
    /// store. Resolve ids back to the live store on every render so a row can
    /// never survive after its book was deleted or updated.
    private var liveBooks: [BookshelfBook] {
        books.compactMap { appState.bookshelfStore.book(id: $0.id) }
    }

    private var liveDisplayBooks: [BookshelfBook] {
        let base = selectedGroupName == nil ? liveBooks : liveBooks.filter { $0.groupName == selectedGroupName }
        let query = debouncedSearchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(query) ||
            $0.author.lowercased().contains(query)
        }
    }

    private var visibleBookIDs: Set<String> {
        Set(liveDisplayBooks.map(\.id))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                    TextField("搜索书名或作者", text: $searchKeyword)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    if !searchKeyword.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            searchKeyword = ""
                            debouncedSearchKeyword = ""
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
                .background(AppTheme.elevatedCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                if !appState.bookshelfStore.groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            groupChip("全部", selected: selectedGroupName == nil) { selectedGroupName = nil }
                            ForEach(appState.bookshelfStore.groups) { group in
                                groupChip(group.name, selected: selectedGroupName == group.name) {
                                    selectedGroupName = group.name
                                }
                            }
                        }
                    }
                }
                if liveDisplayBooks.isEmpty {
                    EmptyStateCard(
                        systemImage: "books.vertical",
                        title: selectedGroupName == nil ? "\(title)暂无书籍" : "该分组暂无书籍",
                        message: selectedGroupName == nil ? "返回主页导入或搜索书籍后会显示在这里。" : "长按书籍可移动到其他分组。"
                    )
                } else {
                    ForEach(liveDisplayBooks) { book in
                        Group {
                            if isManaging {
                                Button {
                                    toggleSelection(book.id)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedBookIDs.contains(book.id) ? "checkmark.circle.fill" : "circle")
                                            .font(.title3)
                                            .foregroundStyle(selectedBookIDs.contains(book.id) ? AppTheme.accent : .secondary)
                                        collectionBookLabel(book)
                                    }
                                }
                            } else {
                                NavigationLink {
                                    BookshelfReaderGatewayView(book: book)
                                } label: {
                                    collectionBookLabel(book)
                                }
                            }
                        }
                        .buttonStyle(PressableScaleButtonStyle())
                        .simultaneousGesture(TapGesture().onEnded {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            appState.bookshelfStore.markUpdatesSeen(bookID: book.id)
                        })
                        .contextMenu {
                            Button {
                                selectedBookForDetail = book
                            } label: {
                                Label("书籍详情", systemImage: "info.circle")
                            }
                            if !appState.bookshelfStore.groups.isEmpty {
                                Menu("移动到分组") {
                                    Button("全部") { appState.bookshelfStore.moveBooks(bookIDs: [book.id], toGroupName: nil) }
                                    ForEach(appState.bookshelfStore.groups) { group in
                                        Button(group.name) { appState.bookshelfStore.moveBooks(bookIDs: [book.id], toGroupName: group.name) }
                                    }
                                }
                            }
                            Button("从书架删除", role: .destructive) {
                                appState.bookshelfStore.remove(bookID: book.id)
                            }
                        }
                    }
                }
            }
            .padding(AppTheme.pagePadding)
        }
        .scrollDismissesKeyboard(.interactively)
        .pageBackground()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !books.isEmpty {
                    Button(isManaging ? "完成" : "管理") {
                        withAnimation(.easeOut(duration: 0.18)) {
                            isManaging.toggle()
                            if !isManaging { selectedBookIDs.removeAll() }
                        }
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        groupName = ""
                        showGroupEditor = true
                    } label: {
                        Label("新建分组", systemImage: "folder.badge.plus")
                    }
                    if !appState.bookshelfStore.groups.isEmpty {
                        Divider()
                        ForEach(appState.bookshelfStore.groups) { group in
                            Button(role: .destructive) {
                                if selectedGroupName == group.name { selectedGroupName = nil }
                                appState.bookshelfStore.deleteGroup(id: group.id)
                            } label: {
                                Label("删除 \(group.name)", systemImage: "trash")
                            }
                        }
                    }
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("管理分组")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isManaging {
                VStack(spacing: 8) {
                    HStack(spacing: 14) {
                        Button("全选") { selectedBookIDs = visibleBookIDs }
                        Button("反选") { selectedBookIDs = visibleBookIDs.subtracting(selectedBookIDs) }
                        Button("清空") { selectedBookIDs.removeAll() }
                        Spacer()
                        Text("已选 \(selectedBookIDs.count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold))

                    HStack(spacing: 10) {
                        Button {
                            appState.bookshelfStore.markUpdatesSeen(bookIDs: selectedBookIDs)
                            selectedBookIDs.removeAll()
                        } label: {
                            Label("标记已读", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedBookIDs.isEmpty)

                        Button {
                            let selectedBooks = liveBooks.filter { selectedBookIDs.contains($0.id) }
                            let text = selectedBooks.map { "- 《" + $0.title + "》 " + $0.author + " (" + ($0.currentChapterTitle ?? $0.latestChapterTitle ?? "未读") + ")" }.joined(separator: "\n")
                            UIPasteboard.general.string = text
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        } label: {
                            Label("导出", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedBookIDs.isEmpty)

                        Button(role: .destructive) { confirmBatchDelete = true } label: {
                            Label("删除", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedBookIDs.isEmpty)

                        Menu {
                            Button("移出分组") {
                                appState.bookshelfStore.moveBooks(bookIDs: selectedBookIDs, toGroupName: nil)
                                selectedBookIDs.removeAll()
                            }
                            ForEach(appState.bookshelfStore.groups) { group in
                                Button(group.name) {
                                    appState.bookshelfStore.moveBooks(bookIDs: selectedBookIDs, toGroupName: group.name)
                                    selectedBookIDs.removeAll()
                                }
                            }
                        } label: {
                            Label("移动", systemImage: "folder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedBookIDs.isEmpty || appState.bookshelfStore.groups.isEmpty)
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
            }
        }
        .alert("新建分组", isPresented: $showGroupEditor) {
            TextField("分组名称", text: $groupName)
            Button("取消", role: .cancel) {}
            Button("保存") {
                appState.bookshelfStore.createGroup(name: groupName)
            }
        } message: {
            Text("分组用于整理书架，不会改变书籍内容或阅读进度。")
        }
        .alert("删除选中的书籍？", isPresented: $confirmBatchDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                appState.bookshelfStore.removeBooks(bookIDs: selectedBookIDs)
                selectedBookIDs.removeAll()
                isManaging = false
            }
        } message: {
            Text("将从书架删除 \(selectedBookIDs.count) 本书，阅读进度也会一并移除。")
        }
        .sheet(item: $selectedBookForDetail) { book in
            NavigationStack {
                BookDetailView(book: book.asSearchBook)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") {
                                selectedBookForDetail = nil
                            }
                        }
                    }
            }
        }
        .task(id: searchKeyword) {
            if searchKeyword.isEmpty {
                debouncedSearchKeyword = ""
                return
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            debouncedSearchKeyword = searchKeyword
        }
    }

    private func collectionBookLabel(_ book: BookshelfBook) -> some View {
        HStack(spacing: 14) {
            AsyncBookCover(urlString: book.coverURL, width: 58, height: 82)
                .overlay(alignment: .topTrailing) {
                    if book.hasUpdates {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 10, height: 10)
                            .overlay {
                                Circle().stroke(Color.white, lineWidth: 1.2)
                            }
                            .offset(x: 3, y: -3)
                            .shadow(color: .red.opacity(0.5), radius: 3)
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(book.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                Text(book.author).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Text(book.currentChapterTitle ?? book.latestChapterTitle ?? "尚未开始阅读")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !isManaging {
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func toggleSelection(_ id: String) {
        if selectedBookIDs.contains(id) { selectedBookIDs.remove(id) } else { selectedBookIDs.insert(id) }
    }

    private func groupChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(selected ? AppTheme.accent : AppTheme.card, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

private struct PressableScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.105), value: configuration.isPressed)
    }
}

struct AsyncBookCover: View {
    let urlString: String?
    var width: CGFloat? = nil
    let height: CGFloat

    var body: some View {
        Group {
            if let urlString, let url = URL(string: urlString) {
                CachedRemoteImage(url: url) { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .overlay {
                Image(systemName: "book.closed")
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}
