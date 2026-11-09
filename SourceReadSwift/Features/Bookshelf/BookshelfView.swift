import SwiftUI
import UniformTypeIdentifiers

struct BookshelfView: View {
    var onRequestGlobalSearch: () -> Void = {}
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var bookHero
    @AppMotion private var motion
    @State private var showFileImporter = false
    @State private var importMessage: String?
    @State private var isRefreshingBooks = false
    @State private var isImportingBook = false
    @State private var bookImportTask: Task<Void, Never>?
    @State private var contextualBookRoute: ContextualBookRoute?
    @State private var bookToRemove: BookshelfBook?
    @State private var shelfReturnOrder: [String] = []
    /// Cached result of `ShelfProjection`. Nil means the first pass still
    /// needs to compute it; afterwards a store/filter change refreshes it.
    @State private var shelfProjection: [BookshelfBook]?
    /// A pushed detail/reader keeps this view alive but offscreen. Store
    /// notifications must not rebuild the filter/sort while the reader is
    /// scrolling; `onAppear` refreshes once when the shelf comes back.
    /// Reference flag: tab appear/disappear must not invalidate the whole shelf body.
    @State private var shelfVisibility = ShelfVisibilityFlag()
    private var isShelfVisible: Bool {
        get { shelfVisibility.isVisible }
        nonmutating set { shelfVisibility.isVisible = newValue }
    }
    /// Store writes that landed while the shelf was pushed away. Without this
    /// flag every tab return re-filtered and re-sorted the whole shelf even
    /// when nothing had changed, stealing the first frames of the transition.
    @State private var shelfProjectionNeedsRefresh = false
    @State private var deskReturnOrder: [String] = []
    @AppStorage("settings.themeMode") private var themeModeRawValue = ThemeMode.system.rawValue
    @AppStorage("bookshelf.isGridMode") private var isGridMode = true
    @AppStorage("bookshelf.sortMode") private var sortModeRawValue = BookshelfSortMode.recentRead.rawValue
    @State private var selectedMainGroup: String? = nil
    @State private var searchKeyword = ShelfFilterSeed.query
    @State private var selectedMediaFilter: String? = nil
    @State private var showsShelfFilters = false
    @State private var usesThemeShelfLayout = true
    /// AppState no longer forwards shelf writes. Bump this after the store has
    /// settled so the group chips and membership rows pick up structural
    /// changes without re-evaluating on every reading-progress tick.
    @State private var shelfDataRevision = 0
    @State private var readingBookID: String?
    @AppStorage("settings.readingDeskEnabled") private var readingDeskEnabled = true
    @AppStorage("settings.floatingReadingDeskEnabled") private var floatingReadingDeskEnabled = true
    @StateObject private var readingCoverHandoff = ReadingCoverHandoff()
    /// Scroll-collapsing navigation chrome. `shelfChromeGate` owns the offset
    /// history so 120 Hz scrolling never writes SwiftUI state per frame, and
    /// `collapsesShelfChrome` only flips at the two thresholds.
    @State private var collapsesShelfChrome = false
    @State private var shelfChromeGate = ScrollChromeGate()
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRaw) ?? .classic }

    /// Shared by the offset reader inside the scroll content and the collapse
    /// modifier on the scroll view itself.
    private static let shelfScrollSpace = "bookshelf.scroll"

    private enum ContextualBookRoute {
        case read(BookshelfBook, coverFrame: UIImage?)
        case detail(BookshelfBook, placement: String)
    }

    enum BookshelfSortMode: String, CaseIterable, Identifiable {
        case recentRead = "最近阅读"
        case added = "最近添加"
        case title = "书名排序"
        case progress = "阅读进度"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .recentRead: return "clock"
            case .added: return "calendar.badge.plus"
            case .title: return "textformat.abc"
            case .progress: return "chart.bar.fill"
            }
        }
    }

    private var recentBooks: [BookshelfBook] {
        appState.bookshelfStore.recentBooks
    }

    private var updatedBooks: [BookshelfBook] {
        appState.bookshelfStore.updatedBooks
    }

    private var allBooks: [BookshelfBook] {
        appState.bookshelfStore.books
    }

    private func mediaKind(for book: BookshelfBook) -> BookSourceKind? {
        if let kind = book.mediaKind { return kind }
        if book.sourceURL == "local://comic" { return .comic }
        if book.sourceURL.hasPrefix("local://") { return nil }
        return appState.sourceStore.source(for: book.sourceURL)?.sourceKind
    }


    private var displayedShelfBooks: [BookshelfBook] {
        shelfProjection ?? makeShelfProjection()
    }

    private func makeShelfProjection() -> [BookshelfBook] {
        ShelfProjection.books(
            allBooks,
            group: selectedMainGroup,
            media: selectedMediaFilter,
            query: searchKeyword,
            sort: BookshelfSortMode(rawValue: sortModeRawValue) ?? .recentRead,
            returnOrder: shelfReturnOrder,
            mediaKind: { mediaKind(for: $0) }
        )
    }

    /// Called only when an input changed. Keeping the result in `@State` stops
    /// `pinReturnOrder` and the return transition from re-filtering the shelf.
    private func refreshShelfProjection() {
        let next = makeShelfProjection()
        // `onAppear` runs on every tab return; assigning an equal array still
        // invalidates the whole shelf body and costs a second layout pass.
        guard shelfProjection != next else { return }
        shelfProjection = next
    }

    var body: some View {
        let _ = shelfDataRevision
        return NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppLayout.sectionGap) {
                    readingSection
                    shelfSection
                }
                .padding(.horizontal, AppTheme.pagePadding)
                // RootTabView already owns tab-bar/safe-area clearance.
                .padding(.bottom, AppLayout.contentTail)
                .reportsScrollOffsetWhenPreferenceIsUsed(in: Self.shelfScrollSpace)
            }
            .collapsingNavigationBarModern(
                in: Self.shelfScrollSpace,
                gate: shelfChromeGate,
                collapsed: $collapsesShelfChrome
            )
            .refreshable {
                clearReturnOrder()
                revealShelfChrome()
                await refreshBookshelf()
            }
            .onAppear {
                isShelfVisible = true
                if shelfProjection == nil {
                    refreshShelfProjection()
                    shelfProjectionNeedsRefresh = false
                } else if shelfProjectionNeedsRefresh {
                    // Let the tab/pop transition finish before sorting the
                    // shelf. The stale projection is visually identical unless
                    // progress actually changed, and a frame of old metadata is
                    // cheaper than a dropped animation frame.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 120_000_000)
                        guard isShelfVisible else { return }
                        shelfProjectionNeedsRefresh = false
                        refreshShelfProjection()
                    }
                }
            }
            .onDisappear { isShelfVisible = false }
            .onReceive(appState.bookshelfStore.$books.dropFirst()) { _ in
                // A pushed reader keeps this view in the hierarchy. Refreshing
                // behind its opening transition re-sorted the shelf in the
                // exact frames the hero zoom was settling.
                guard isShelfVisible, contextualBookRoute == nil else {
                    shelfProjectionNeedsRefresh = true
                    return
                }
                // @Published emits from willSet, so reading the store
                // synchronously here would project the previous array.
                Task { @MainActor in refreshShelfProjection() }
            }
            .onReceive(appState.bookshelfStore.$groups.dropFirst()) { _ in
                shelfDataRevision &+= 1
                if !isShelfVisible { shelfProjectionNeedsRefresh = true }
            }
            .onReceive(appState.sourceStore.$sources) { _ in
                guard isShelfVisible, contextualBookRoute == nil else {
                    shelfProjectionNeedsRefresh = true
                    return
                }
                refreshShelfProjection()
            }
            .onChange(of: sortModeRawValue) { _ in clearReturnOrder() }
            .onChange(of: searchKeyword) { _ in clearReturnOrder() }
            .onChange(of: selectedMainGroup) { _ in clearReturnOrder() }
            .onChange(of: selectedMediaFilter) { _ in clearReturnOrder() }
            .onChange(of: themeRaw) { _ in usesThemeShelfLayout = true }
            .background(bookshelfBackdrop)
            .overlay(alignment: .topTrailing) { shelfChromeReveal }
            .onChange(of: floatingReadingDeskEnabled) { isEnabled in
                if !isEnabled { readingCoverHandoff.clear() }
            }
            .onChange(of: readingDeskEnabled) { isEnabled in
                if !isEnabled { readingCoverHandoff.clear() }
            }
            .navigationTitle("主页")
            .navigationBarTitleDisplayMode(theme.usesNeutralGlass ? .large : .inline)
            .scrollCollapsedNavigationBar(collapsesShelfChrome)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // Keep one global-search entry visible above the fold. The
                    // shelf header scrolls under the reading desk, so a button
                    // there is not reachable on launch; the toolbar is.
                    Button {
                        onRequestGlobalSearch()
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.usesNeutralGlass ? theme.primaryInk : AppTheme.accent)
                    }
                    .accessibilityLabel("全网搜书")
                    .accessibilityIdentifier(usesNativeTabs ? "bookshelf.globalSearch" : "bookshelf.header.globalSearch")

                    NavigationLink {
                        ReadingStatsView()
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(theme.usesNeutralGlass ? theme.primaryInk : AppTheme.accent)
                    }
                    .accessibilityLabel("阅读统计看板")

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showFileImporter = true
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.usesNeutralGlass ? theme.primaryInk : AppTheme.accent)
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
                        UTType(filenameExtension: "epub") ?? UTType(importedAs: "org.idpf.epub-container"),
                        UTType(filenameExtension: "cbz") ?? .zip
                    ],
                    onPick: { urls in
                        showFileImporter = false
                        importLocalBook(.success(urls))
                    },
                    onCancel: { showFileImporter = false }
                )
                .ignoresSafeArea()
            }
            .navigationDestination(isPresented: Binding(
                get: { contextualBookRoute != nil }, set: { if !$0 { contextualBookRoute = nil } }
            )) {
                if let route = contextualBookRoute {
                    switch route {
                    case .read(let book, let coverFrame):
                        BookshelfReaderGatewayView(book: book, onRequestExit: { contextualBookRoute = nil })
                            .readerOpeningPresentation(for: managedOpeningBook(book), coverFrame: coverFrame, usesDeskHero: true)
                            .bookHeroDestination("continue|" + book.id, in: bookHero)
                            .environment(\.readingCoverHandoff, readingDeskEnabled && floatingReadingDeskEnabled ? readingCoverHandoff : nil)
                    case .detail(let book, let placement):
                        detailDestination(book, placement: placement)
                    }
                }
            }
            .alert("从书架删除？", isPresented: Binding(
                get: { bookToRemove != nil }, set: { if !$0 { bookToRemove = nil } }
            ), presenting: bookToRemove) { book in
                Button("从书架删除", role: .destructive) {
                    clearReturnOrder()
                    appState.bookshelfStore.remove(bookID: book.id)
                    bookToRemove = nil
                }
                Button("取消", role: .cancel) { bookToRemove = nil }
            } message: { book in
                Text("将移除《\(book.title)》及其书架阅读进度。")
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
                            Button("取消导入", action: cancelBookImport)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("bookshelf.cancelImport")
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
        let _ = themeModeRawValue
        return AppPagePaper(theme: theme).ignoresSafeArea()
    }

    /// A long shelf leaves no other way back once the bar is gone, so a parked
    /// chip on the trailing edge restores it on tap.
    @ViewBuilder
    private var shelfChromeReveal: some View {
        if collapsesShelfChrome {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                revealShelfChrome()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.usesNeutralGlass ? theme.primaryInk : AppTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(AppPressStyle())
            .padding(.trailing, 10)
            .accessibilityIdentifier("bookshelf.revealChrome")
            .accessibilityLabel("显示导航栏")
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Resets the gate as well as the flag: after a refresh or a popped detail the
    /// next offset arrives against stale history otherwise.
    private func revealShelfChrome() {
        shelfChromeGate.reset()
        guard collapsesShelfChrome else { return }
        withAnimation(motion.animation(.expansion)) { collapsesShelfChrome = false }
    }

    private var readingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collectionHeader(title: "正在阅读", books: recentBooks)
            if !recentBooks.isEmpty, !(readingDeskEnabled && floatingReadingDeskEnabled) {
                Text("把这一刻，留给下一页。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if recentBooks.isEmpty {
                emptyImportCard
            } else {
                if readingDeskEnabled {
                    let books = deskBooks
                    ReadingDeskPager(books: books, selection: Binding(
                        get: { ReadingDeskSelection.resolve(readingBookID, in: books) },
                        set: { readingBookID = $0 }), usesFloatingStyle: floatingReadingDeskEnabled,
                        preferredFloatingHeight: theme.usesNeutralGlass ? 194 : theme.isAtelier ? 230 : 288, card: { heroCard($0) })
                } else if let book = recentBooks.first { heroCard(book) }
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
                    .buttonStyle(AppPressStyle())
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

    private var shelfSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            TextField("在书架查找", text: $searchKeyword)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .accessibilityIdentifier("bookshelf.filterQuery")
            if !searchKeyword.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    searchKeyword = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(AppPressStyle())
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(theme.usesNeutralGlass ? theme.controlFill : AppTheme.elevatedCard)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var shelfSection: some View {
        let shelfBooks = displayedShelfBooks
        return VStack(alignment: .leading, spacing: 8) {
            shelfHeader

            if !allBooks.isEmpty, showsShelfFilters {
                shelfSearchBar

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        mainGroupChip("全部", isSelected: selectedMainGroup == nil && selectedMediaFilter == nil) {
                            selectedMainGroup = nil
                            selectedMediaFilter = nil
                        }

                        // Media format quick filters
                        mainGroupChip("小说", isSelected: selectedMediaFilter == "novel") {
                            selectedMediaFilter = selectedMediaFilter == "novel" ? nil : "novel"
                        }
                        mainGroupChip("漫画", isSelected: selectedMediaFilter == "comic") {
                            selectedMediaFilter = selectedMediaFilter == "comic" ? nil : "comic"
                        }
                        mainGroupChip("有声", isSelected: selectedMediaFilter == "audio") {
                            selectedMediaFilter = selectedMediaFilter == "audio" ? nil : "audio"
                        }
                        mainGroupChip("影视", isSelected: selectedMediaFilter == "video") {
                            selectedMediaFilter = selectedMediaFilter == "video" ? nil : "video"
                        }
                        mainGroupChip("本地", isSelected: selectedMediaFilter == "local") {
                            selectedMediaFilter = selectedMediaFilter == "local" ? nil : "local"
                        }

                        // Custom user groups
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
            } else if shelfBooks.isEmpty {
                compactEmptyState(icon: "folder", title: "没有符合筛选的书籍", message: "尝试清空搜索词或切换分组与类型")
            } else if showsGridShelf {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16),
                                   count: theme.usesFramedShelf || typeSize.isAccessibilitySize ? 2 : 3),
                    spacing: 18
                ) {
                    ForEach(shelfBooks) { book in
                        bookshelfGridCard(book)
                    }
                }
            } else {
                LazyVStack(spacing: AppLayout.rowGap) {
                    ForEach(shelfBooks) { book in
                        bookshelfRow(book)
                    }
                }
            }
        }
    }

    private var shelfHeader: some View {
        HStack(spacing: 12) {
            NavigationLink {
                BookshelfCollectionView(title: "书架", books: allBooks,
                    onRequestGlobalSearch: onRequestGlobalSearch)
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
            .buttonStyle(AppPressStyle())

            Spacer()

            if !allBooks.isEmpty {
                Button {
                    withAnimation(motion.animation(.expansion)) { showsShelfFilters.toggle() }
                } label: {
                    Image(systemName: hasShelfFilter ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(hasShelfFilter ? AppTheme.accent : theme.secondaryInk)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppPressStyle())
                .accessibilityIdentifier("bookshelf.filters")
                .accessibilityLabel(showsShelfFilters ? "收起书架筛选" : "展开书架筛选")
                .accessibilityValue(hasShelfFilter ? "已启用筛选" : "未筛选")

                Menu {
                    ForEach(BookshelfSortMode.allCases) { mode in
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            sortModeRawValue = mode.rawValue
                        } label: {
                            if sortModeRawValue == mode.rawValue {
                                Label(mode.rawValue, systemImage: "checkmark")
                            } else {
                                Label(mode.rawValue, systemImage: mode.icon)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.usesNeutralGlass ? theme.secondaryInk : .secondary)
                        .frame(width: 44, height: 44)
                        .background(theme.usesNeutralGlass ? Color.clear : Color.secondary.opacity(0.12), in: Circle())
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("排序方式")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(motion.animation(.expansion)) {
                        isGridMode = !showsGridShelf
                        usesThemeShelfLayout = false
                    }
                } label: {
                    Image(systemName: showsGridShelf ? "rectangle.grid.1x2" : "square.grid.2x2")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.usesNeutralGlass ? theme.secondaryInk : .secondary)
                        .frame(width: 44, height: 44)
                        .background(theme.usesNeutralGlass ? Color.clear : Color.secondary.opacity(0.12), in: Circle())
                        .contentShape(Rectangle())
                }
                .buttonStyle(AppPressStyle())
                .accessibilityLabel(showsGridShelf ? "切换为列表视图" : "切换为网格视图")
            }
        }
    }

    private var usesNativeTabs: Bool {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    private var hasShelfFilter: Bool {
        selectedMainGroup != nil || selectedMediaFilter != nil || !searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var showsGridShelf: Bool {
        usesThemeShelfLayout && theme.homeComposition == .index ? false : isGridMode
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
                .modifier(BrandFilterFinish(isSelected: isSelected, legacyFill: AppTheme.card))
        }
        .buttonStyle(AppPressStyle())
    }

    @ViewBuilder
    private func collectionHeader(title: String, books: [BookshelfBook]) -> some View {
        NavigationLink {
            BookshelfCollectionView(title: title, books: books,
                onRequestGlobalSearch: onRequestGlobalSearch)
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
        .buttonStyle(AppPressStyle())
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
        .buttonStyle(AppPressStyle())
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
        guard bookImportTask == nil else {
            importMessage = "上一项导入正在取消，请稍后再导入。"
            return
        }
        isImportingBook = true
        bookImportTask = Task { @MainActor in
            defer {
                Task { @MainActor in
                    isImportingBook = false
                    bookImportTask = nil
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
                let parserTask = Task.detached(priority: .userInitiated) {
                    try Task.checkCancellation()
                    let localURL = try PickedDocumentAccess.copiedURL(from: url)
                    try Task.checkCancellation()
                    // Same container sniff as the share-sheet entry: never decide
                    // "this is TXT" from the copied file name alone.
                    if localURL.pathExtension.lowercased() == "cbz" {
                        return try LocalComicBookParser().parse(fileURL: localURL)
                    } else if LocalEPUBBookParser.looksLikeEPUB(localURL) {
                        return try LocalEPUBBookParser().parse(fileURL: localURL)
                    } else {
                        let data = try Data(contentsOf: localURL)
                        return LocalTxtSmartDivider().divide(data: data, fileName: localURL.lastPathComponent)
                    }
                }
                let parsed = try await withTaskCancellationHandler(operation: {
                    try await parserTask.value
                }, onCancel: { parserTask.cancel() })
                if Task.isCancelled {
                    try await Task.detached(priority: .utility) {
                        try LocalComicBookParser.removeFiles(for: BookshelfBook(localTextBook: parsed))
                    }.value
                    throw CancellationError()
                }
                // This task owns MainActor: do not suspend between the final
                // cancellation check and committing the imported book.
                appState.bookshelfStore.addLocalTextBook(parsed)
                HapticFeedback.success()
                importMessage = parsed.mediaKind == .comic
                    ? "已导入《\(parsed.title)》，共 \(parsed.paragraphs.count) 页漫画。"
                    : "已导入《\(parsed.title)》，共 \(parsed.chapters.count) 章、\(parsed.paragraphs.count) 段。"
            } catch is CancellationError {
                await MainActor.run {
                    if isImportingBook { importMessage = "已取消导入，未加入书架。" }
                }
            } catch {
                await MainActor.run {
                    HapticFeedback.error()
                    importMessage = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func cancelBookImport() {
        bookImportTask?.cancel()
        isImportingBook = false
        importMessage = "已取消导入，未加入书架。"
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
            return BookshelfRefreshCandidate(bookID: book.id, source: source.resolvingMediaKind(book.mediaKind),
                                              book: book.asSearchBook)
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
                                    totalChapters: chapters.count,
                                    coverURL: detail.coverUrl
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
                    case .success(let bookID, let latestChapterTitle, let intro, let totalChapters, let coverURL):
                        appState.bookshelfStore.updateDetails(
                            bookID: bookID,
                            latestChapterTitle: latestChapterTitle,
                            intro: intro,
                            totalChapters: totalChapters,
                            coverURL: coverURL
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

    private var deskBooks: [BookshelfBook] {
        let books = ReadingDeskSelection.books(from: recentBooks)
        return BookReturnOrder.restore(books, ids: deskReturnOrder) ?? books
    }

    private func pinReturnOrder(placement: String) {
        // 返回首页时 onAppear 会再次调用；内容没变就不写 @State，
        // 否则会多触发一整轮 body 求值，返回手感直接变卡。
        if placement == "continue" {
            let next = deskBooks.map(\.id)
            guard deskReturnOrder != next else { return }
            deskReturnOrder = next
        } else {
            let next = displayedShelfBooks.map(\.id)
            guard shelfReturnOrder != next else { return }
            shelfReturnOrder = next
        }
    }

    private func clearReturnOrder() {
        shelfReturnOrder = []
        deskReturnOrder = []
        refreshShelfProjection()
    }

    private func detailDestination(_ book: BookshelfBook, placement: String) -> some View {
        BookDetailView(book: book.asSearchBook)
            .bookHeroDestination(placement + "|" + book.id, in: bookHero)
            .environment(\.readingCoverHandoff, readingDeskEnabled ? readingCoverHandoff : nil)
            .onAppear { pinReturnOrder(placement: placement) }
    }

    @ViewBuilder private func bookDestination(_ book: BookshelfBook, placement: String) -> some View {
        // 书架（网格 / 列表）一律进详情；只有「正在阅读」卡片直接进阅读。
        detailDestination(book, placement: placement)
    }

    private func managedOpeningBook(_ book: BookshelfBook) -> BookshelfBook? {
        guard readingDeskEnabled, floatingReadingDeskEnabled else { return nil }
        return (mediaKind(for: book) ?? .text) == .text ? book : nil
    }

    private func heroCard(_ book: BookshelfBook) -> some View {
        readingDeskEntry(book)
            .contextMenu {
                readingDeskBookActions(book)
                Divider()
                Toggle("悬浮玻璃书台", isOn: $floatingReadingDeskEnabled)
                    .accessibilityIdentifier("bookshelf.floatingDeskToggle")
            }
    }

    private func readingDeskEntry(_ book: BookshelfBook) -> some View {
        Button {
            guard contextualBookRoute == nil else { return }
            pinReturnOrder(placement: "continue")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            contextualBookRoute = .read(book, coverFrame: readingCoverHandoff.frame(for: book))
        } label: {
            Group {
                if theme.homeComposition != .readingDesk, readingDeskEnabled {
                    ThemedReadingCard(book: book, theme: theme, heroNamespace: bookHero)
                } else if theme.usesFloatingBook && readingDeskEnabled && floatingReadingDeskEnabled {
                    ForestReadingCard(book: book, heroNamespace: bookHero, theme: theme)
                } else {
                    ReadingHeroCard(book: book, heroNamespace: bookHero, usesSpatialStyle: readingDeskEnabled,
                        usesFloatingStyle: floatingReadingDeskEnabled)
                }
            }
                .environment(\.readingCoverHandoff, readingDeskEnabled && floatingReadingDeskEnabled ? readingCoverHandoff : nil)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 3)
        }
        .accessibilityIdentifier("bookshelf.continue." + book.id)
        .buttonStyle(ReadingDeskTapStyle())
    }

    @ViewBuilder private func readingDeskBookActions(_ book: BookshelfBook) -> some View {
        Button {
            guard contextualBookRoute == nil else { return }
            pinReturnOrder(placement: "continue")
            contextualBookRoute = .detail(book, placement: "continue")
        } label: {
            Label("书籍详情", systemImage: "info.circle")
        }
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            clearReturnOrder()
            appState.bookshelfStore.togglePin(bookID: book.id)
        } label: {
            Label(book.isPinned ? "取消置顶" : "置顶书籍", systemImage: book.isPinned ? "pin.slash" : "pin")
        }
        Button("从书架删除", role: .destructive) {
            bookToRemove = book
        }
    }

    private func updateRow(_ book: BookshelfBook) -> some View {
        // The rule is shelf-card -> detail, only the reading desk opens prose.
        // This row used to push the reader directly and quietly bypassed it.
        NavigationLink {
            detailDestination(book, placement: "update")
        } label: {
            HStack(spacing: 14) {
                AsyncBookCover(urlString: book.coverURL, width: 70, height: 100, baseURLString: book.bookURL, sourceURLString: book.sourceURL)
                    .bookHeroSource("update|" + book.id, in: bookHero)

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
            .glassPanel(cornerRadius: 18, material: .thinMaterial, shadowOpacity: 0)
        }
        .buttonStyle(PressableScaleButtonStyle())
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            appState.bookshelfStore.markUpdatesSeen(bookID: book.id)
        })
    }

    private func bookshelfRow(_ book: BookshelfBook) -> some View {
        NavigationLink {
            bookDestination(book, placement: "list")
        } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 14))
            layout {
                ShelfBookCover(book: book, width: 52, height: 72, theme: theme)
                    .environment(\.readingCoverHandoff, readingDeskEnabled ? readingCoverHandoff : nil)
                    .bookHeroSource("list|" + book.id, in: bookHero)
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
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                        if book.hasUpdates {
                            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(theme.secondaryInk)
                                .accessibilityLabel("有更新")
                        }
                    }
                    Text(book.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    if let current = book.currentChapterTitle {
                        Text("读到：\(current)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .modifier(BookshelfRowSurface(theme: theme))
        }
        .buttonStyle(BookOpenPressStyle())
        .accessibilityIdentifier("bookshelf.list." + book.id)
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .swipeActions(edge: .leading) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                clearReturnOrder()
                appState.bookshelfStore.togglePin(bookID: book.id)
            } label: {
                Label(book.isPinned ? "取消置顶" : "置顶", systemImage: book.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            Button("删除", role: .destructive) {
                bookToRemove = book
            }
        }
        .contextMenu {
            Button {
                pinReturnOrder(placement: "list")
                contextualBookRoute = .detail(book, placement: "list")
            } label: {
                Label("书籍详情", systemImage: "info.circle")
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                clearReturnOrder()
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
                bookToRemove = book
            }
        }
    }

    private func bookshelfGridCard(_ book: BookshelfBook) -> some View {
        NavigationLink {
            bookDestination(book, placement: "grid")
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ShelfBookCover(book: book, width: nil, height: 120, theme: theme)
                    .environment(\.readingCoverHandoff, readingDeskEnabled ? readingCoverHandoff : nil)
                    .bookHeroSource("grid|" + book.id, in: bookHero)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .top, spacing: 4) {
                        Text(book.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(theme.primaryInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if book.isPinned {
                            Image(systemName: "pin.fill").font(.caption2).foregroundStyle(theme.secondaryInk)
                                .accessibilityLabel("已置顶")
                        }
                        if book.hasUpdates {
                            Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(theme.secondaryInk)
                                .accessibilityLabel("有更新")
                        }
                    }
                    .frame(minHeight: 34, alignment: .topLeading)

                    Text(book.author.isEmpty ? (book.groupName ?? "未知作者") : book.author)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(theme.usesFramedShelf ? 12 : 0)
            .background {
                if theme.usesFramedShelf {
                    AppTheme.card.clipShape(AppThemeCardShape(theme: theme, radius: theme.radius), style: FillStyle(eoFill: true))
                        .overlay { AppThemeOrnament(theme: theme, isCard: true) }
                }
            }
        }
        .buttonStyle(BookOpenPressStyle())
        .accessibilityIdentifier("bookshelf.grid." + book.id)
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .contextMenu {
            Button {
                pinReturnOrder(placement: "grid")
                contextualBookRoute = .detail(book, placement: "grid")
            } label: {
                Label("书籍详情", systemImage: "info.circle")
            }
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                clearReturnOrder()
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
                bookToRemove = book
            }
        }
    }
}

private final class ShelfVisibilityFlag {
    var isVisible = true
}

private struct BookshelfRefreshCandidate: Sendable {
    let bookID: String
    let source: BookSource
    let book: SearchBook
}

private enum BookshelfRefreshResult: Sendable {
    case success(bookID: String, latestChapterTitle: String?, intro: String?, totalChapters: Int, coverURL: String?)
    case failure(bookID: String, message: String)
}

private struct BookshelfCollectionView: View {
    @EnvironmentObject private var appState: AppState
    let title: String
    let books: [BookshelfBook]
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRaw) ?? .classic }
    @State private var selectedGroupName: String?
    @State private var showGroupEditor = false
    @State private var groupName = ""
    @State private var isManaging = false
    @State private var selectedBookIDs: Set<String> = []
    @State private var confirmBatchDelete = false
    @State private var contextDetailBook: BookshelfBook?
    @State private var searchKeyword = ""
    @State private var debouncedSearchKeyword = ""
    @Namespace private var collectionHero
    /// The root page owns the tab/overlay switch, so the collection screen only
    /// forwards the request instead of guessing how global search is presented.
    private let onRequestGlobalSearch: () -> Void

    init(title: String, books: [BookshelfBook], startsManaging: Bool = false,
         onRequestGlobalSearch: @escaping () -> Void = {}) {
        self.title = title
        self.books = books
        self.onRequestGlobalSearch = onRequestGlobalSearch
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

    /// The collection screen pushes the same detail destination as the shelf, so
    /// both entry points share the hero zoom transition.
    private func detailDestination(_ book: BookshelfBook, placement: String) -> some View {
        BookDetailView(book: book.asSearchBook)
            .bookHeroDestination(placement + "|" + book.id, in: collectionHero)
    }

    var body: some View {
        // 派生集合一次求值、全 body 复用：原来 body 内两处引用会各跑一遍 filter。
        let displayBooks = liveDisplayBooks
        return ScrollView {
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
                        .buttonStyle(AppPressStyle())
                    }
                    // 全局搜索入口：iOS 26 是系统 .search tab，26 以下在自绘栏；
                    // 这里保留一个稳定的可访问入口，两套架构共用同一个 identifier。
                    Button {
                        onRequestGlobalSearch()
                    } label: {
                        Image(systemName: "globe")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(AppPressStyle())
                    .accessibilityLabel("全网搜书")
                    .accessibilityIdentifier("bookshelf.collection.globalSearch")
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
                if displayBooks.isEmpty {
                    EmptyStateCard(
                        systemImage: "books.vertical",
                        title: selectedGroupName == nil ? "\(title)暂无书籍" : "该分组暂无书籍",
                        message: selectedGroupName == nil ? "返回主页导入或搜索书籍后会显示在这里。" : "长按书籍可移动到其他分组。"
                    )
                } else {
                    ForEach(displayBooks) { book in
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
                                // 书架卡片点击只进详情；走 push 而不是 sheet，
                                // 才能吃到 bookHeroDestination 的 zoom 转场（sheet 没有转场）。
                                NavigationLink {
                                    detailDestination(book, placement: "collection")
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
                                contextDetailBook = book
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
        // iOS 16 paints the large title directly above the first row; the
        // custom search field then reads as if it overlaps the navigation bar.
        // The collection is a utility screen, so a compact title is both safer
        // and more space-efficient.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("标记已读")
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
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("导出")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedBookIDs.isEmpty)

                        Button(role: .destructive) { confirmBatchDelete = true } label: {
                            Label("删除", systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("删除")
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
                                .labelStyle(.iconOnly)
                                .accessibilityLabel("移动")
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
        .navigationDestination(isPresented: Binding(
            get: { contextDetailBook != nil },
            set: { if !$0 { contextDetailBook = nil } }
        )) {
            if let book = contextDetailBook {
                detailDestination(book, placement: "collection")
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
            ShelfBookCover(book: book, width: 58, height: 82, theme: theme)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(book.title).font(.headline).foregroundStyle(.primary).lineLimit(2)
                    if book.hasUpdates {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.secondary)
                            .accessibilityLabel("有更新")
                    }
                }
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
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .modifier(BrandFilterFinish(isSelected: selected, legacyFill: AppTheme.card))
        }
        .buttonStyle(AppPressStyle())
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
        BookOpenPressStyle().makeBody(configuration: configuration)
    }
}

struct AsyncBookCover: View {
    @Environment(\.displayScale) private var displayScale
    @Environment(\.readingCoverHandoff) private var readingCoverHandoff

    /// 占位块要跟着承载它的底色走：白卡片上用浅灰，深色主视觉上用半透明白。
    enum Style {
        case card
        case onDark
    }

    let urlString: String?
    var width: CGFloat? = nil
    let height: CGFloat
    var style: Style = .card
    /// Detail-page URL used to resolve protocol-relative or root-relative
    /// covers returned by imported sources.
    var baseURLString: String? = nil
    /// Book-source home page, used when `bookURL` was persisted in relative
    /// form by an older build.
    var sourceURLString: String? = nil
    var onImageLoad: ((UIImage?) -> Void)? = nil
    var title: String? = nil
    var contentMode: ContentMode = .fill
    var prefersDeskRaster = false
    var cornerRadius: CGFloat = 10
    var usesPlainPlaceholder = false

    var body: some View {
        Group {
            if let url = CoverURLResolver.url(from: urlString, base: baseURLString, fallbackBase: sourceURLString) {
                CachedRemoteImage(url: url, contentMode: contentMode, maxPixelSize: coverMaxPixelSize,
                    reuseCoverBytes: true, onImageLoad: { image in
                    if let image { readingCoverHandoff?.retain(image, for: url) }
                    onImageLoad?(image ?? readingCoverHandoff?.image(for: url))
                }) { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: urlString) {
            if CoverURLResolver.url(from: urlString, base: baseURLString, fallbackBase: sourceURLString) == nil {
                onImageLoad?(nil)
            }
        }
    }

    /// Decode at the size this cover is actually drawn. The shelf grid shows
    /// ~110 pt covers; downloading a 1000 px JPEG and keeping the full texture
    /// alive for every row was the main scroll hitch on the home page.
    private var coverMaxPixelSize: CGFloat {
        let points = max(width ?? 220, height)
        if prefersDeskRaster { return ReadingDeskCoverRaster.maximumPixelSize(points: points, scale: displayScale) }
        return points * max(displayScale, 1)
    }

    @ViewBuilder private var placeholder: some View {
        if let url = CoverURLResolver.url(from: urlString, base: baseURLString, fallbackBase: sourceURLString),
           let image = readingCoverHandoff?.image(for: url) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else if usesPlainPlaceholder {
            PlainShelfJacket(title: title)
        } else {
            BookCoverPlaceholder(title: title, height: height, isOnDark: style == .onDark)
        }
    }
}

/// A UI test seeds the shelf query through the launch-argument domain
/// (`-bookshelf.filterQuerySeed 剑来`), so the collapse/restore assertions read
/// real state instead of depending on the simulator keyboard synthesizing CJK
/// text. A normal launch leaves the key absent and the shelf starts unfiltered.
private enum ShelfFilterSeed {
    static var query: String {
        UserDefaults.standard.string(forKey: "bookshelf.filterQuerySeed") ?? ""
    }
}
