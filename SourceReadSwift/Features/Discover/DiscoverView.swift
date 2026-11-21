import SwiftUI
import UIKit

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DiscoverViewModel
    private let mode: Mode
    private let showsCloseButton: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var hasBoundModels = false
    @StateObject private var exploreViewModel = ExploreViewModel()
    @State private var pendingShelfAddBook: SearchBook?
    @State private var shelfAddNotice: ShelfAddNotice?
    @State private var shelfNoticeTask: Task<Void, Never>?
    @State private var showSmartWebReader = false
    @State private var showExploreSourcePickerSheet = false
    @State private var showExploreCategoryPicker = false
    @State private var selectedAggregatedBookForSources: AggregatedSearchBook? = nil
    @State private var detectedClipboardSourceURL: String? = nil
    @State private var lastCheckedPasteboardChangeCount: Int = -1
    @State private var isImportingClipboardSource = false
    @State private var clipboardImportToast: String? = nil
    @AppStorage("discover_search_history") private var searchHistoryJSON: String = "[]"
    /// Result presentation for the aggregated list. A three-column cover grid
    /// is much denser than the old full-width row on a phone.
    @AppStorage("discover.resultLayout") private var discoverResultLayoutRaw = DiscoverResultLayout.list.rawValue
    /// Cached decode of `searchHistoryJSON`. Decoding inside `body` ran a full
    /// JSON decode (and two array copies) on every layout pass of the search tab,
    /// including every streaming update during a search.
    @State private var cachedSearchHistory: [String] = []
    /// Progress changes do not change search-result membership. Keep the
    /// snapshot so an offscreen Discover tab is not redrawn on every save.
    @State private var cachedShelfMembership: BookshelfMembership?
    @State private var shelfMembershipDirty = true
    @State private var visibilityFlag = DiscoverVisibilityFlag()
    @State private var clipboardCheckTask: Task<Void, Never>?

    private struct ShelfAddNotice: Identifiable {
        let id = UUID()
        let didSave: Bool
        var title: String { didSave ? "已加入书架" : "未能保存到书架，请重试" }
    }

    private static func decodeSearchHistory(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let list = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return list
    }

    private var hotKeywords: [String] {
        switch currentSourceKind {
        case .some(.comic):
            return Self.comicHotKeywords
        case .some(.audio):
            return Self.audioHotKeywords
        case .some(.video):
            return Self.videoHotKeywords
        default:
            return Self.textHotKeywords
        }
    }

    // Shared constants: `body` reads these once per pass, so they must not
    // allocate a fresh array each time.
    private static let comicHotKeywords = ["海贼王", "咒术回战", "一拳超人", "火影忍者", "间谍过家家", "进击的巨人", "电锯人", "死神"]
    private static let audioHotKeywords = ["凡人修仙传", "鬼吹灯", "雪中悍刀行", "盗墓笔记", "大奉打更人", "吞噬星空", "三体", "剑来"]
    private static let videoHotKeywords = ["三体", "庆余年", "狂飙", "繁花", "星际穿越", "流浪地球", "奥本海默", "沙丘"]
    private static let textHotKeywords = ["诡秘之主", "凡人修仙传", "三体", "剑来", "斗罗大陆", "遮天", "红楼梦", "西游记", "三国演义", "水浒传"]

    private func saveSearchKeyword(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var current = cachedSearchHistory
        current.removeAll(where: { $0 == trimmed })
        current.insert(trimmed, at: 0)
        if current.count > 10 {
            current = Array(current.prefix(10))
        }
        cachedSearchHistory = current
        if let data = try? JSONEncoder().encode(current),
           let str = String(data: data, encoding: .utf8) {
            searchHistoryJSON = str
        }
    }

    private func clearSearchHistory() {
        cachedSearchHistory = []
        searchHistoryJSON = "[]"
    }

    enum DiscoverResultLayout: String, CaseIterable, Identifiable {
        case list
        case grid
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "square.grid.2x2"
            }
        }
    }

    private var resultLayout: DiscoverResultLayout {
        DiscoverResultLayout(rawValue: discoverResultLayoutRaw) ?? .list
    }

    enum Mode: Equatable {
        case explore
        case search
    }

    init(viewModel: DiscoverViewModel? = nil, mode: Mode = .explore, showsCloseButton: Bool = false) {
        self.mode = mode
        self.showsCloseButton = showsCloseButton
        self._viewModel = ObservedObject(wrappedValue: viewModel ?? DiscoverViewModel())
    }

    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    private var usesForestGlass: Bool { themeRaw == AppVisualTheme.forest.rawValue }

    var body: some View {
        NavigationStack {
            if mode == .search {
                discoveryContent
                    .searchable(text: $viewModel.keyword, placement: showsCloseButton ? .navigationBarDrawer(displayMode: .always) : .automatic,
                                prompt: "搜索书名或作者")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(of: .search) { submitSearch() }
                    .onChange(of: viewModel.keyword) { value in
                        if value.count > 200 { viewModel.keyword = String(value.prefix(200)) }
                        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                           viewModel.hasSearchState {
                            viewModel.clearSearch()
                        }
                    }
            } else {
                discoveryContent
            }
        }
    }

    private var discoveryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if detectedClipboardSourceURL != nil {
                    clipboardSourceBanner
                }

                mediumFilterPillBar

                if mode == .search {
                    bookSearchTab
                } else {
                    bookExploreTab
                }
            }
            .padding(.horizontal, AppTheme.pagePadding)
            .padding(.bottom, AppLayout.contentTail)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .refreshable {
            if mode == .explore {
                await exploreViewModel.refresh()
            }
        }
        .pageBackground()
        .overlay(alignment: .bottom) {
            if let notice = shelfAddNotice {
                Label(notice.title, systemImage: notice.didSave ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(notice.title)
                    .accessibilityIdentifier("discover.shelfAddNotice")
            }
        }
        .navigationTitle(mode == .search ? "搜书" : AppNavigationLabels.findBooks)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("globalSearch.close")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showSmartWebReader = true
                } label: {
                    Image(systemName: "safari")
                        .foregroundStyle(usesForestGlass ? AppVisualTheme.forest.primaryInk : AppTheme.accent)
                }
                .accessibilityLabel("智能网页阅读")
            }
        }
        .task {
            guard !hasBoundModels else { return }
            hasBoundModels = true
            if mode == .search {
                cachedSearchHistory = Self.decodeSearchHistory(searchHistoryJSON)
            } else {
                exploreViewModel.bind(appState: appState)
            }
        }
        .onChange(of: searchHistoryJSON) { value in
            let decoded = Self.decodeSearchHistory(value)
            if decoded != cachedSearchHistory {
                cachedSearchHistory = decoded
            }
        }
        .onAppear {
            visibilityFlag.isVisible = true
            if shelfMembershipDirty {
                let membership = BookshelfMembership(books: appState.bookshelfStore.books)
                if cachedShelfMembership != membership { cachedShelfMembership = membership }
                shelfMembershipDirty = false
            }
            scheduleClipboardCheck()
        }
        .onDisappear {
            visibilityFlag.isVisible = false
            clearShelfNotice()
            clipboardCheckTask?.cancel()
            clipboardCheckTask = nil
        }
        .onReceive(appState.bookshelfStore.$books) { books in
            guard visibilityFlag.isVisible else {
                shelfMembershipDirty = true
                return
            }
            let membership = BookshelfMembership(books: books)
            if cachedShelfMembership != membership { cachedShelfMembership = membership }
            shelfMembershipDirty = false
        }
        .alert("书源导入结果", isPresented: Binding(
            get: { clipboardImportToast != nil },
            set: { if !$0 { clipboardImportToast = nil } }
        )) {
            Button("确定", role: .cancel) { clipboardImportToast = nil }
        } message: {
            if let msg = clipboardImportToast {
                Text(msg)
            }
        }
        .confirmationDialog(
            "加入书架？",
            isPresented: Binding(
                get: { pendingShelfAddBook != nil },
                set: { if !$0 { pendingShelfAddBook = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("加入书架") {
                guard let book = pendingShelfAddBook else { return }
                appState.bookshelfStore.addOrUpdate(book)
                pendingShelfAddBook = nil
                showShelfNotice(didSave: appState.bookshelfStore.lastError == nil)
            }
            .accessibilityIdentifier("discover.confirmShelfAdd")
            Button("取消", role: .cancel) {
                pendingShelfAddBook = nil
            }
        } message: {
            if let book = pendingShelfAddBook {
                Text("确认把《\(book.name)》加入书架并开始跟踪阅读进度？")
            }
        }
        .sheet(isPresented: $showSmartWebReader) {
            SmartWebReaderView()
        }
        .sheet(item: $selectedAggregatedBookForSources) { aggregated in
            NavigationStack {
                List {
                    Section {
                        ForEach(aggregated.sources) { sourceBook in
                            NavigationLink {
                                BookDetailView(book: sourceBook, availableSources: aggregated.sources)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(sourceBook.sourceName)
                                            .font(.headline)
                                        Spacer()
                                        if bookshelfMembership.contains(sourceBook) {
                                            Label("已在书架", systemImage: "checkmark.circle")
                                                .font(.caption)
                                                .foregroundStyle(AppTheme.accent)
                                        }
                                    }
                                    if let latest = sourceBook.lastChapter?.nilIfEmpty {
                                        Text(latest)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    } header: {
                        Text("《\(aggregated.name)》 · \(aggregated.selectionTitle)")
                    }
                }
                .navigationTitle("选择书源")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func submitSearch() {
        saveSearchKeyword(viewModel.keyword)
        viewModel.startSearch()
        dismissKeyboardNow()
    }

    private func showShelfNotice(didSave: Bool) {
        shelfNoticeTask?.cancel()
        let notice = ShelfAddNotice(didSave: didSave)
        shelfAddNotice = notice
        // Own the deadline at the action boundary. A confirmation sheet or a
        // result-list rebuild can unmount the overlay before its own task runs.
        shelfNoticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled, shelfAddNotice?.id == notice.id else { return }
            shelfAddNotice = nil
            shelfNoticeTask = nil
        }
    }

    private func clearShelfNotice() {
        shelfNoticeTask?.cancel()
        shelfNoticeTask = nil
        shelfAddNotice = nil
    }

    private var currentSourceKind: BookSourceKind? {
        mode == .search ? viewModel.selectedSourceKind : exploreViewModel.selectedSourceKind
    }

    private var mediumFilterPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                mediumPill(title: "全部", icon: "square.grid.2x2", isSelected: currentSourceKind == nil) {
                    setMediumFilter(nil)
                }
                ForEach(BookSourceKind.allCases) { kind in
                    mediumPill(
                        title: kind.displayName,
                        icon: kind.systemImage,
                        isSelected: currentSourceKind == kind
                    ) {
                        setMediumFilter(kind)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        // Keep the old visual spacing without taking away the pills' 44 pt hit area.
        .padding(.vertical, -5)
    }

    private func setMediumFilter(_ kind: BookSourceKind?) {
        guard currentSourceKind != kind else { return }
        if mode == .search {
            viewModel.selectSourceKind(kind)
        } else {
            exploreViewModel.selectSourceKind(kind)
        }
    }

    private func mediumPill(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .modifier(BrandFilterFinish(isSelected: isSelected, legacyFill: Color(UIColor.secondarySystemGroupedBackground)))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var bookSearchTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 14) {
                matchModePicker
                searchResultScopeBar
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: viewModel.matchMode) { _ in
                viewModel.applyMatchMode()
            }

            if viewModel.hasSearchState {
                Text("搜索结果")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)
                    .accessibilityAddTraits(.isHeader)
                if let coverage = viewModel.sourceCoverage {
                    Text(coverage.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("discover.sourceCoverage")
                }
            }

            content
        }
    }

    private var matchModePicker: some View {
        HStack {
            Spacer(minLength: 0)
            Picker("匹配方式", selection: $viewModel.matchMode) {
                ForEach(SearchMatchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 156, height: 44)
            .accessibilityIdentifier("discover.matchMode")
        }
    }

    /// 取消单独的筛选输入框：两个词义按钮直接复用搜索关键词，第三个入口
    /// 选择具体书源，并把下一次在线搜索限定在该书源内。
    private var searchResultScopeBar: some View {
        HStack(spacing: 6) {
            if viewModel.hasSearchState {
                resultScopeChip(.title)
                resultScopeChip(.author)
            }
            searchSourceMenu
            if viewModel.resultFilterScope != .all || viewModel.selectedSourceURL != nil {
                Button {
                    viewModel.resultFilterScope = .all
                    let hadSelectedSource = viewModel.selectedSourceURL != nil
                    viewModel.clearSearchSource()
                    viewModel.applyResultFilter()
                    if hadSelectedSource { restartSearchAfterSourceChange() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除结果筛选")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        // Keep the group identifier from propagating into each chip and menu.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("discover.resultScopeBar")
    }

    private func resultScopeChip(_ scope: SearchResultFilterScope) -> some View {
        let isSelected = viewModel.resultFilterScope == scope
        return Button {
            viewModel.resultFilterScope = isSelected ? .all : scope
            viewModel.applyResultFilter()
        } label: {
            Text(scope.title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? AppTheme.accent : Color(UIColor.secondarySystemGroupedBackground))
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(AppPressStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("discover.resultScope." + scope.rawValue)
    }

    private var searchSourceMenu: some View {
        Menu {
            Button {
                viewModel.clearSearchSource()
                restartSearchAfterSourceChange()
            } label: {
                Label("全部已启用书源", systemImage: viewModel.selectedSourceURL == nil ? "checkmark" : "books.vertical")
            }
            Divider()
            ForEach(searchableSources) { source in
                Button {
                    viewModel.setSearchSource(url: source.bookSourceUrl)
                    restartSearchAfterSourceChange()
                } label: {
                    Label(source.bookSourceName,
                          systemImage: viewModel.selectedSourceURL == source.bookSourceUrl ? "checkmark" : "books.vertical")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 12, weight: .semibold))
                Text(viewModel.selectedSourceName ?? "全部已启用书源")
                    .font(.system(size: 12, weight: viewModel.selectedSourceURL == nil ? .medium : .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: 94, alignment: .leading)
            .foregroundStyle(viewModel.selectedSourceURL == nil ? Color.primary : AppTheme.accent)
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(viewModel.selectedSourceURL == nil ? Color(UIColor.secondarySystemGroupedBackground) : AppTheme.accent.opacity(0.12))
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(viewModel.selectedSourceName ?? "全部已启用书源")
        .accessibilityIdentifier("discover.searchSource")
    }

    private var searchableSources: [BookSource] {
        appState.sourceStore.sources.filter { source in
            guard source.enabled, source.hasSearchEntry else { return false }
            if let kind = viewModel.selectedSourceKind {
                return source.canSearch(mediaKind: kind)
            }
            return true
        }
    }

    private func restartSearchAfterSourceChange() {
        if !viewModel.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            viewModel.startSearch()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isSearching && viewModel.results.isEmpty {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text("正在搜索")
                    .font(.headline)
                Text("已检测 \(viewModel.checkedSourceCount)/\(viewModel.enabledSourceCount) 个源")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("取消搜索") {
                    viewModel.cancelSearch()
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        } else if let error = viewModel.errorMessage, viewModel.results.isEmpty {
            EmptyStateCard(systemImage: "exclamationmark.triangle", title: "搜索失败", message: error)
        } else if viewModel.results.isEmpty, viewModel.wasCancelled {
            EmptyStateCard(systemImage: "pause.circle", title: "搜索已取消",
                           message: "已检测 \(viewModel.checkedSourceCount)/\(viewModel.enabledSourceCount) 个源，可再次提交搜索。")
        } else if viewModel.hasUnfilteredResults && viewModel.results.isEmpty {
            EmptyStateCard(systemImage: "line.3.horizontal.decrease.circle", title: "没有符合筛选的结果", message: "换一个筛选词，或切换书名、作者、来源范围。")
        } else if viewModel.results.isEmpty, viewModel.hasFinishedSearch {
            EmptyStateCard(systemImage: "magnifyingglass", title: viewModel.hasRawResults ? "没有精准匹配" : "没有搜索结果", message: viewModel.hasRawResults ? "书源已返回候选书籍，切换模糊模式可查看相关结果。" : "书源已完成搜索，尝试更换关键词或书源。")
        } else if viewModel.results.isEmpty {
            searchInitialStateView
        } else {
            resultsList
        }
    }

    private var searchInitialStateView: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Search History Section
            if !cachedSearchHistory.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("搜索历史", systemImage: "clock")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            clearSearchHistory()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空搜索历史")
                    }

                    FlowLayout(spacing: 8) {
                        ForEach(cachedSearchHistory, id: \.self) { item in
                            Button {
                                viewModel.keyword = item
                                saveSearchKeyword(item)
                                viewModel.startSearch()
                            } label: {
                                Text(item)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(UIColor.secondarySystemGroupedBackground), in: Capsule())
                                    .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            // Trending / Hot Searches Section
            VStack(alignment: .leading, spacing: 12) {
                Label("热门推荐", systemImage: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(hotKeywords, id: \.self) { item in
                        Button {
                            viewModel.keyword = item
                            saveSearchKeyword(item)
                            viewModel.startSearch()
                        } label: {
                            HStack(spacing: 4) {
                                Text(item)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.primary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(UIColor.secondarySystemGroupedBackground), in: Capsule())
                            .overlay(Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Hint Text
            HStack {
                Spacer()
                Text("输入书名、作者或关键词，从启用的源流书源中全网检索")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(.top, 16)
        }
        .padding(.vertical, 12)
    }

    /// One shelf-membership snapshot per list pass. The rows used to call
    /// `bookshelfStore.contains(_:)` (a linear scan over the shelf) up to three
    /// times each, on every layout pass, which is what made long result lists
    /// stutter. The predicate deliberately mirrors `BookshelfStore.resolvedIndex`
    /// (exact `id`, else `local://` rows matched by `bookURL`).
    private var bookshelfMembership: BookshelfMembership {
        cachedShelfMembership ?? BookshelfMembership(books: appState.bookshelfStore.books)
    }

    struct BookshelfMembership: Equatable {
        private let ids: Set<String>
        private let localBookURLs: Set<String>

        init(books: [BookshelfBook]) {
            ids = Set(books.lazy.flatMap { [$0.id, $0.asSearchBook.id] })
            localBookURLs = Set(books.map(\.bookURL))
        }

        func contains(_ book: SearchBook) -> Bool {
            if ids.contains(book.id) { return true }
            guard book.sourceUrl.hasPrefix("local://") else { return false }
            return localBookURLs.contains(book.bookUrl)
        }

        func preferredBook(for edition: AggregatedSearchBook) -> SearchBook {
            edition.sources.first(where: contains) ?? edition.primaryBook
        }
    }

    private var resultsList: some View {
        let shelf = bookshelfMembership
        return LazyVStack(spacing: 14) {
            VStack(spacing: 8) {
                HStack {
                    Text("已检测 \(viewModel.checkedSourceCount)/\(viewModel.enabledSourceCount) 个源 · 命中 \(viewModel.hitSourceCount) 个源 · 结果 \(viewModel.totalResultCount) 条\(viewModel.filterSummary)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if viewModel.isSearching {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Button("取消") {
                                viewModel.cancelSearch()
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
                if viewModel.wasCancelled {
                    Label("已取消，保留已找到的结果", systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Text(viewModel.displayMode == .aggregated
                        ? "聚合为 \(viewModel.aggregatedResults.count) 部书籍"
                        : "按书源分组显示")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if usesForestGlass {
                        BrandSegmentedControl("结果显示", selection: $viewModel.displayMode,
                            options: SearchDisplayMode.allCases.map { ($0, $0.title) })
                            .frame(maxWidth: 152)
                    } else {
                        HStack(spacing: 0) {
                            ForEach(SearchDisplayMode.allCases) { mode in
                                let isSelected = viewModel.displayMode == mode
                                Button {
                                    viewModel.displayMode = mode
                                } label: {
                                    Text(mode.title)
                                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background {
                                            if isSelected {
                                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                    .fill(AppTheme.accent)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(2)
                        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }

                    if viewModel.displayMode == .aggregated {
                        Button {
                            discoverResultLayoutRaw = resultLayout == .list
                                ? DiscoverResultLayout.grid.rawValue
                                : DiscoverResultLayout.list.rawValue
                        } label: {
                            Image(systemName: resultLayout == .list ? "square.grid.2x2" : "list.bullet")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 30, height: 26)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(resultLayout == .list ? "切换为网格" : "切换为列表")
                    }
                }
            }

            if !viewModel.sourceFailures.isEmpty {
                DisclosureGroup("\(viewModel.failedSourceCount) 个源检测失败") {
                    VStack(alignment: .leading, spacing: 5) {
                        if viewModel.failedSourceCount > viewModel.sourceFailures.count {
                            Text("显示最近 \(viewModel.sourceFailures.count) 项失败")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(viewModel.sourceFailures.enumerated()), id: \.offset) { _, failure in
                            Text(failure)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }

            resultPageControls
            if viewModel.displayMode == .aggregated {
                if resultLayout == .grid {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 14)],
                        spacing: 18
                    ) {
                        ForEach(viewModel.pagedAggregatedResults) { item in
                            aggregatedBookGridCard(item, shelf: shelf)
                        }
                    }
                } else {
                    ForEach(viewModel.pagedAggregatedResults) { item in
                        aggregatedBookCard(item, shelf: shelf)
                    }
                }
            } else {
                ForEach(viewModel.pagedGroupedResults) { group in
                    Section {
                        ForEach(group.books) { book in
                            searchResultCard(book, inShelf: shelf.contains(book))
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Image(systemName: "books.vertical")
                            Text(group.source)
                                .font(.subheadline.weight(.bold))
                            Text("\(group.books.count) 条")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(AppTheme.accent)
                    }
                }
            }
        }
    }

    private var resultPageControls: some View {
        HStack {
            Button("上一页") { viewModel.resultPage = max(0, viewModel.resultPage - 1) }
                .disabled(viewModel.resultPage == 0)
            Spacer()
            Text("第 \(viewModel.resultPage + 1) / \(viewModel.resultPageCount) 页 · 每页 20 条")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Button("下一页") { viewModel.resultPage = min(viewModel.resultPageCount - 1, viewModel.resultPage + 1) }
                .disabled(viewModel.resultPage + 1 >= viewModel.resultPageCount)
        }
        .buttonStyle(.bordered)
    }

    private func aggregatedBookGridCard(_ item: AggregatedSearchBook, shelf: BookshelfMembership) -> some View {
        let book = shelf.preferredBook(for: item)
        return VStack(alignment: .leading, spacing: 2) {
            NavigationLink {
                BookDetailView(book: book, availableSources: item.sources)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    aggregatedGridCover(item.coverProvider?.coverUrl, base: item.coverProvider?.bookUrl,
                                        source: item.coverProvider?.sourceUrl)
                        .overlay(alignment: .topTrailing) {
                            if shelf.contains(book) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white, Color.green)
                                    .padding(5)
                            }
                        }
                    Text(item.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.author ?? "作者未知")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            if item.sources.count > 1 { sourceSelectionButton(item) }
        }
    }

    private func aggregatedBookCard(_ item: AggregatedSearchBook, shelf: BookshelfMembership) -> some View {
        let book = shelf.preferredBook(for: item)
        let inShelf = shelf.contains(book)
        return HStack(alignment: .top, spacing: 12) {
            NavigationLink {
                BookDetailView(book: book, availableSources: item.sources)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    aggregatedCover(item.coverProvider?.coverUrl, base: item.coverProvider?.bookUrl, source: item.coverProvider?.sourceUrl)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Text(item.author ?? "作者未知")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            HStack(spacing: 3) {
                                Image(systemName: "books.vertical.fill")
                                    .font(.system(size: 10))
                                Text("\(item.sourceCount) 源")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                        }

                        if let latest = item.latestChapter, !latest.isEmpty {
                            Text("最新：\(latest)")
                                .font(.caption)
                                .foregroundStyle(AppTheme.accent)
                                .lineLimit(1)
                        }

                        if let intro = item.intro, !intro.isEmpty {
                            Text(intro)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    if !inShelf {
                        pendingShelfAddBook = book
                    }
                } label: {
                    Image(systemName: inShelf ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .foregroundStyle(inShelf ? Color.green : AppTheme.accent)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(inShelf ? "已在书架" : "加入书架")
                .accessibilityIdentifier("discover.addToShelf")

                if item.sources.count > 1 { sourceSelectionButton(item) }
            }
        }
        .podcastCard()
    }

    private func sourceSelectionButton(_ edition: AggregatedSearchBook) -> some View {
        Button {
            selectedAggregatedBookForSources = edition
        } label: {
            Label(edition.selectionTitle, systemImage: "books.vertical")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.accent)
                .padding(.horizontal, 8)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("为\(edition.name)选择书源")
        .accessibilityValue(edition.selectionTitle)
        .accessibilityIdentifier("discover.sourceVariants")
    }

    @ViewBuilder
    private func aggregatedCover(_ coverUrl: String?, base: String?, source: String?) -> some View {
        if let url = CoverURLResolver.url(from: coverUrl, base: base, fallbackBase: source) {
            CachedRemoteImage(url: url, maxPixelSize: 260) {
                aggregatedCoverPlaceholder
            }
            .frame(width: 64, height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            aggregatedCoverPlaceholder
                .frame(width: 64, height: 86)
        }
    }

    @ViewBuilder
    private func aggregatedGridCover(_ coverUrl: String?, base: String?, source: String?) -> some View {
        Group {
            if let url = CoverURLResolver.url(from: coverUrl, base: base, fallbackBase: source) {
                CachedRemoteImage(url: url, maxPixelSize: 420) { aggregatedCoverPlaceholder }
            } else {
                aggregatedCoverPlaceholder
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var aggregatedCoverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.blue.opacity(0.12))
            .overlay {
                Image(systemName: "book")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
    }

    private func searchResultCard(_ book: SearchBook, inShelf: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink {
                BookDetailView(book: book)
            } label: {
                SearchBookRow(book: book, sourceKind: viewModel.sourceKind(for: book))
            }
            .buttonStyle(.plain)


            Button {
                if !inShelf {
                    pendingShelfAddBook = book
                }
            } label: {
                Image(systemName: inShelf ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(inShelf ? Color.green : AppTheme.accent)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(inShelf ? "已在书架" : "加入书架")
        }
        .podcastCard()
    }

    // MARK: - Clipboard Source Auto-Detection

    private var clipboardSourceBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.title3)
                .foregroundStyle(AppTheme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("检测到剪贴板中的书源")
                    .font(.subheadline.weight(.semibold))
                Text(detectedClipboardSourceURL ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isImportingClipboardSource {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("导入") {
                    importClipboardSource()
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppTheme.prominentFill, in: Capsule())
                .foregroundStyle(AppTheme.prominentInk)

                Button {
                    detectedClipboardSourceURL = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func scheduleClipboardCheck() {
        clipboardCheckTask?.cancel()
        clipboardCheckTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled, visibilityFlag.isVisible else { return }
            checkClipboard()
        }
    }

    private func checkClipboard() {
        let pasteboard = UIPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastCheckedPasteboardChangeCount else { return }
        lastCheckedPasteboardChangeCount = currentChangeCount
        guard pasteboard.hasURLs || pasteboard.hasStrings else { return }
        guard let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
        if text == detectedClipboardSourceURL { return }
        if (text.hasPrefix("http://") || text.hasPrefix("https://")) && (text.contains(".json") || text.contains("source") || text.contains("yuedu") || text.contains("legado") || text.contains("book")) {
            detectedClipboardSourceURL = text
        } else if text.hasPrefix("[") && text.contains("bookSourceName") {
            detectedClipboardSourceURL = text
        }
    }

    private func importClipboardSource() {
        guard let target = detectedClipboardSourceURL else { return }
        isImportingClipboardSource = true
        Task {
            do {
                let report: SourceImportReport
                if target.hasPrefix("http"), let url = URL(string: target) {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    report = try await appState.sourceStore.importJSONDataAsync(data)
                } else {
                    report = try await appState.sourceStore.importJSONAsync(target)
                }
                let count = report.totalAdded + report.totalUpdated
                await MainActor.run {
                    isImportingClipboardSource = false
                    detectedClipboardSourceURL = nil
                    clipboardImportToast = count > 0 ? "已成功导入 \(count) 个书源" : "未解析到有效书源"
                }
            } catch {
                await MainActor.run {
                    isImportingClipboardSource = false
                    clipboardImportToast = "导入失败：\(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Explore Tab

    private var bookExploreTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            if exploreViewModel.availableSources.isEmpty {
                EmptyStateCard(
                    systemImage: "compass.drawing",
                    title: "暂无可探索的书源",
                    message: exploreViewModel.errorMessage
                        ?? "当前启用的书源中未配置分类寻书规则(exploreUrl)。您可以在书源管理中导入更多精品书源。"
                )
            } else {
                sourceSelectorSection

                ExploreSourceControls(controls: exploreViewModel.sourceControls,
                    inputs: $exploreViewModel.sourceInputs, isLoading: exploreViewModel.isLoadingMenu,
                    message: exploreViewModel.sourceActionMessage,
                    onAction: exploreViewModel.performSourceAction)
                categorySelectorSection

                exploreBooksSection
            }
        }
    }

    private var sourceSelectorSection: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(exploreViewModel.availableSources) { source in
                        let isSelected = exploreViewModel.selectedSource?.id == source.id
                        Button {
                            exploreViewModel.selectSource(source)
                        } label: {
                            HStack(spacing: 4) {
                                if source.sourceKind.isStreamMedia {
                                    Image(systemName: source.isMusicSource ? "music.note" : source.sourceKind.systemImage)
                                        .font(.caption2)
                                }
                                Text(source.bookSourceName)
                                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                isSelected ? AppTheme.accent : Color(UIColor.secondarySystemGroupedBackground),
                                in: Capsule()
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            // 「全部源」折叠换源入口
            Button {
                showExploreSourcePickerSheet = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "list.bullet")
                        .font(.caption.weight(.bold))
                    Text("全部源")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color(UIColor.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(AppTheme.accent)
                .overlay {
                    Capsule().stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("展开全部寻书书源列表")
        }
        .sheet(isPresented: $showExploreSourcePickerSheet) {
            ExploreSourceSelectionSheet(viewModel: exploreViewModel)
        }
    }

    private var categorySelectorSection: some View {
        Button { showExploreCategoryPicker = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                Text(exploreViewModel.selectedCategory?.title ?? "选择分类")
                    .lineLimit(1)
                Spacer()
                Text("\(exploreViewModel.categories.count) 个分类").foregroundStyle(.secondary)
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(AppPressStyle())
        .disabled(exploreViewModel.categories.isEmpty)
        .accessibilityIdentifier("discover.chooseCategory")
        .sheet(isPresented: $showExploreCategoryPicker) {
            ExploreCategorySelectionSheet(categories: exploreViewModel.categories,
                selectedID: exploreViewModel.selectedCategory?.id) { category in
                exploreViewModel.selectedGroup = category.group
                exploreViewModel.selectCategory(category)
            }
        }
    }

    private var exploreBooksSection: some View {
        let shelf = bookshelfMembership
        return VStack(spacing: 12) {
            if exploreViewModel.isLoading && exploreViewModel.books.isEmpty {
                VStack(spacing: 16) {
                    ProgressView()
                        .controlSize(.large)
                    Text("正在加载精选分类...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .podcastCard()
            } else if let error = exploreViewModel.errorMessage, exploreViewModel.books.isEmpty {
                EmptyStateCard(
                    systemImage: "exclamationmark.triangle",
                    title: "加载失败",
                    message: error
                )
                Button("重试") {
                    exploreViewModel.loadBooks(page: 1)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            } else if exploreViewModel.books.isEmpty {
                EmptyStateCard(
                    systemImage: "tray",
                    title: "暂无书籍",
                    message: "当前分类下未找到相关小说"
                )
            } else {
                // A failed refresh must not be silent just because a previous
                // page already populated the list.
                if let error = exploreViewModel.errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("重试") {
                                exploreViewModel.loadBooks(page: 1)
                            }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                LazyVStack(spacing: 14) {
                    ForEach(exploreViewModel.books) { book in
                        searchResultCard(book, inShelf: shelf.contains(book))
                            .onAppear {
                                exploreViewModel.loadNextPageIfNeeded(currentItem: book)
                            }
                    }
                }

                if exploreViewModel.isLoadingMore {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在加载更多...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

}

enum SearchDisplayMode: String, CaseIterable, Identifiable {
    case aggregated
    case bySource

    var id: String { rawValue }
    var title: String {
        switch self {
        case .aggregated: return "按书聚合"
        case .bySource: return "按书源"
        }
    }
}

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var keyword = ""
    @Published var displayMode: SearchDisplayMode = .aggregated { didSet { resultPage = 0 } }
    @Published var resultPage = 0
    static let resultPageSize = 20
    var resultPageCount: Int { max(1, (displayCount + Self.resultPageSize - 1) / Self.resultPageSize) }
    private var displayCount: Int { displayMode == .aggregated ? aggregatedResults.count : results.count }
    var pagedAggregatedResults: [AggregatedSearchBook] { ResultPage.slice(aggregatedResults, page: resultPage) }
    var pagedGroupedResults: [ResultGroup] { Self.makeGroupedResults(from: ResultPage.slice(results, page: resultPage)) }
    @Published var matchMode = SearchMatchMode.initial
    @Published var resultFilterScope: SearchResultFilterScope = .all
    @Published var resultFilter = ""
    /// 第三个搜索入口：把在线搜索限定在一个具体书源内。
    @Published private(set) var selectedSourceURL: String?
    @Published private(set) var selectedSourceName: String?
    @Published var selectedSourceKind: BookSourceKind? = nil
    /// Visible, filtered result rows. `didSet` refreshes the derived groupings
    /// once per change; the groupings used to be recomputed on every `body`
    /// read, which is what dropped frames while results streamed in.
    @Published var results: [SearchBook] = [] {
        didSet {
            guard !installingProjection else { return }
            projectionRevision &+= 1
            rebuildDerivedResults()
        }
    }
    private var installingProjection = false
    private var projectionRevision = 0
    @Published private(set) var groupedResults: [ResultGroup] = []
    @Published private(set) var aggregatedResults: [AggregatedSearchBook] = []
    private var unfilteredResults: [SearchBook] = []
    var hasUnfilteredResults: Bool { !unfilteredResults.isEmpty }
    var hasRawResults: Bool { !rawResults.isEmpty }
    @Published private(set) var hasFinishedSearch = false
    @Published private(set) var wasCancelled = false
    /// Typed input wins in every scope; an empty field falls back to the
    /// submitted keyword only when a specific scope is selected.
    private var effectiveResultFilterQuery: String {
        let typed = resultFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        return resultFilterScope == .all ? "" : activeKeyword
    }

    var filterSummary: String {
        effectiveResultFilterQuery.isEmpty ? "" : " · 筛选后 \(results.count) 条"
    }
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hitSourceCount = 0
    @Published var checkedSourceCount = 0
    @Published var totalResultCount = 0
    @Published var sourceFailures: [String] = []
    @Published private(set) var failedSourceCount = 0
    @Published private(set) var sourceCoverage: SourceCoverage?
    var enabledSourceCount: Int { sourceCoverage?.targetCount ?? 0 }

    struct SourceCoverage: Equatable, Sendable {
        let importedCount: Int
        let enabledCount: Int
        let searchableCount: Int
        let targetCount: Int

        var summary: String {
            "已导入 \(importedCount) · 已启用 \(enabledCount) · 可搜索 \(searchableCount) · 本次 \(targetCount)"
        }
    }

    struct ResultGroup: Identifiable, Sendable {
        let source: String
        let sourceURL: String
        let books: [SearchBook]
        var id: String { sourceURL.isEmpty ? source : sourceURL }
    }

    /// Recomputed only when `results` changes, never per layout pass.
    private func rebuildDerivedResults() {
        groupedResults = Self.makeGroupedResults(from: results)
        aggregatedResults = DiscoverSearchAggregation.group(results, kinds: sourceKindCache)
        resultPage = min(resultPage, resultPageCount - 1)
    }

    nonisolated private static func makeGroupedResults(from results: [SearchBook]) -> [ResultGroup] {
        Dictionary(grouping: results, by: { $0.sourceUrl.isEmpty ? $0.sourceName : $0.sourceUrl })
            .map { _, books in
                ResultGroup(source: books.first?.sourceName ?? "未知书源", sourceURL: books.first?.sourceUrl ?? "", books: books)
            }
            .sorted {
                if $0.source == $1.source { return $0.id < $1.id }
                return $0.source.localizedStandardCompare($1.source) == .orderedAscending
            }
    }

    struct ResultProjection: Sendable {
        let results: [SearchBook]
        let groups: [ResultGroup]
        let aggregated: [AggregatedSearchBook]
    }

    nonisolated static func makeProjection(_ books: [SearchBook], kinds: [String: BookSourceKind],
                                           kind: BookSourceKind?, sourceURL: String? = nil, query: String,
                                           scope: SearchResultFilterScope,
                                           dynamicSourceURLs: Set<String> = []) -> ResultProjection {
        var base = books
        if let sourceURL, !sourceURL.isEmpty {
            base = base.filter { $0.sourceUrl == sourceURL }
        }
        if let kind {
            base = base.filter { matchesMediaKind($0, kind: kind, kinds: kinds, dynamicSourceURLs: dynamicSourceURLs) }
        }
        let filtered = SearchResultFilter.apply(base, query: query, scope: scope)
        return .init(results: filtered, groups: makeGroupedResults(from: filtered),
                     aggregated: DiscoverSearchAggregation.group(filtered, kinds: kinds))
    }

    nonisolated private static func matchesMediaKind(_ book: SearchBook, kind: BookSourceKind,
                                                     kinds: [String: BookSourceKind],
                                                     dynamicSourceURLs: Set<String>) -> Bool {
        if let resolvedKind = book.mediaKind { return resolvedKind == kind }
        // Aggregates may decide a result's medium only after loading its directory.
        if dynamicSourceURLs.contains(book.sourceUrl) { return true }
        return (kinds[book.sourceUrl] ?? .text) == kind
    }

    /// A streamed batch does all folding, grouping and source aggregation off
    /// the main actor. A newer filter/reset invalidates the whole snapshot.
    func installRankedResults(_ books: [SearchBook]) async {
        unfilteredResults = books
        refreshSourceKindCacheIfNeeded()
        projectionRevision &+= 1
        let revision = projectionRevision
        let kinds = sourceKindCache
        let dynamicSourceURLs = dynamicMediaSourceURLs
        let kind = selectedSourceKind
        let query = effectiveResultFilterQuery
        let scope = resultFilterScope
        let sourceURL = selectedSourceURL
        let projection = await Task.detached(priority: .userInitiated) {
            Self.makeProjection(books, kinds: kinds, kind: kind, sourceURL: sourceURL, query: query, scope: scope,
                                dynamicSourceURLs: dynamicSourceURLs)
        }.value
        guard !Task.isCancelled, projectionRevision == revision else { return }
        installingProjection = true
        results = projection.results
        groupedResults = projection.groups
        aggregatedResults = projection.aggregated
        installingProjection = false
        resultPage = min(resultPage, resultPageCount - 1)
    }

    private weak var appState: AppState?
    private var activeSearchID: UUID?
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var activeKeyword = ""
    private var lastSubmittedKeyword = ""
    private var rawResults: [SearchBook] = []
    /// Identity of every row already merged into `rawResults`. Appending with a
    /// set keeps each streamed batch O(batch), instead of re-running the whole
    /// de-duplication pass over the growing list (O(n²) over a search).
    private var mergedBookIDs: Set<String> = []
    private var sourceKindCache: [String: BookSourceKind] = [:]
    private var dynamicMediaSourceURLs: Set<String> = []
    private var sourceKindCacheToken = ""
    private var filterDebounceTask: Task<Void, Never>?

    func bind(appState: AppState) {
        self.appState = appState
        sourceKindCacheToken = ""
    }

    /// Appends only unseen rows; returns whether anything was added.
    @discardableResult
    private func mergeBooks(_ books: [SearchBook]) -> Bool {
        var appended = false
        for book in books {
            guard let key = SearchBookMatcher.identityKey(for: book) else { continue }
            if mergedBookIDs.insert(key).inserted {
                rawResults.append(book)
                appended = true
            }
        }
        return appended
    }

    var hasSearchState: Bool {
        isSearching || hasFinishedSearch || wasCancelled || hasRawResults || !results.isEmpty || errorMessage != nil
    }

    func clearSearch() {
        cancelSearch()
        filterDebounceTask?.cancel()
        filterDebounceTask = nil
        activeKeyword = ""
        hasFinishedSearch = false
        wasCancelled = false
        results = []
        unfilteredResults = []
        rawResults = []
        mergedBookIDs = []
        totalResultCount = 0
        hitSourceCount = 0
        checkedSourceCount = 0
        sourceFailures = []
        failedSourceCount = 0
        sourceCoverage = nil
        lastSubmittedKeyword = ""
        errorMessage = nil
        resultFilter = ""
        resultFilterScope = .all
        // Set the text last so the view's empty-keyword observer sees an
        // already-reset model and cannot recursively trigger another reset.
        keyword = ""
    }

    func cancelSearch() {
        projectionRevision &+= 1
        wasCancelled = isSearching
        if wasCancelled { lastSubmittedKeyword = "" }
        searchGeneration &+= 1
        searchTask?.cancel()
        searchTask = nil
        activeSearchID = nil
        isSearching = false
    }

    func startSearch() {
        let submitted = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !submitted.isEmpty,
           submitted == lastSubmittedKeyword,
           !isSearching,
           (hasFinishedSearch || hasRawResults || !results.isEmpty) {
            return
        }
        lastSubmittedKeyword = submitted
        isSearching = !submitted.isEmpty
        wasCancelled = false
        searchGeneration &+= 1
        let generation = searchGeneration
        searchTask?.cancel()
        searchTask = Task { @MainActor [weak self] in
            await self?.search(generation: generation)
            guard let self, self.searchGeneration == generation else { return }
            self.searchTask = nil
        }
    }

    func applyResultFilter() {
        // Invalidate any detached ranking/projection already in flight. Without
        // this revision bump, a late search batch can overwrite a filter the
        // user just selected.
        projectionRevision &+= 1
        refreshSourceKindCacheIfNeeded()
        var base = unfilteredResults
        if let selectedSourceURL, !selectedSourceURL.isEmpty {
            base = base.filter { $0.sourceUrl == selectedSourceURL }
        }
        if let kind = selectedSourceKind {
            base = base.filter { book in
                Self.matchesMediaKind(book, kind: kind, kinds: sourceKindCache,
                                      dynamicSourceURLs: dynamicMediaSourceURLs)
            }
        }
        // A filter changes the number of rows, so an old page number can point
        // past the new last page (or at a page that only exists in the old
        // projection). Always return to the first page of the new result set.
        resultPage = 0
        results = SearchResultFilter.apply(base, query: effectiveResultFilterQuery, scope: resultFilterScope)
    }

    /// Typing in the filter field re-folds every field of every row, so the text
    /// field is debounced instead of filtering on each keystroke.
    func applyResultFilterDebounced() {
        filterDebounceTask?.cancel()
        filterDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, let self else { return }
            self.applyResultFilter()
        }
    }

    /// O(1) medium lookup. `SourceStore.source(for:)` is a linear scan over all
    /// sources and the row views called it on every layout pass.
    func sourceKind(for book: SearchBook) -> BookSourceKind {
        refreshSourceKindCacheIfNeeded()
        return book.mediaKind ?? sourceKindCache[book.sourceUrl] ?? .text
    }

    private func refreshSourceKindCacheIfNeeded() {
        let token = String(appState?.sourceStore.sourcesRevision ?? 0)
        if token != sourceKindCacheToken {
            let sources = appState?.sourceStore.sources ?? []
            var map: [String: BookSourceKind] = [:]
            var dynamicSourceURLs: Set<String> = []
            map.reserveCapacity(sources.count)
            for source in sources {
                map[source.bookSourceUrl] = source.sourceKind
                if source.hasDynamicMediaType { dynamicSourceURLs.insert(source.bookSourceUrl) }
            }
            sourceKindCache = map
            dynamicMediaSourceURLs = dynamicSourceURLs
            sourceKindCacheToken = token
        }
    }

    func selectSourceKind(_ kind: BookSourceKind?) {
        guard selectedSourceKind != kind else { return }
        // A concrete source that cannot serve the new medium must not survive
        // and silently produce an empty search.
        if let kind, let url = selectedSourceURL,
           let source = appState?.sourceStore.source(for: url),
           !source.canSearch(mediaKind: kind) {
            selectedSourceURL = nil
            selectedSourceName = nil
        }
        selectedSourceKind = kind
        applyResultFilter()
        if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastSubmittedKeyword = ""
            startSearch()
        }
    }

    /// Set by Global Search (or the source menu) before `startSearch()`.
    func setSearchSource(url: String?) {
        let next = url?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        guard selectedSourceURL != next else { return }
        selectedSourceURL = next
        selectedSourceName = next.flatMap { appState?.sourceStore.source(for: $0)?.bookSourceName }
        lastSubmittedKeyword = ""
    }

    func clearSearchSource() {
        setSearchSource(url: nil)
    }

    func applyMatchMode() {
        guard !activeKeyword.isEmpty, !rawResults.isEmpty else { return }
        unfilteredResults = filtered(rawResults, keyword: activeKeyword)
        totalResultCount = rawResults.count
        applyResultFilter()
    }

    func search(generation: Int) async {
        guard generation == searchGeneration else { return }
        guard let appState else { isSearching = false; return }
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            activeSearchID = nil
            isSearching = false
            errorMessage = nil
            results = []
            unfilteredResults = []
            rawResults = []
            mergedBookIDs = []
            totalResultCount = 0
            hitSourceCount = 0
            checkedSourceCount = 0
            sourceFailures = []
            failedSourceCount = 0
            sourceCoverage = nil
            return
        }
        activeKeyword = keyword
        lastSubmittedKeyword = keyword
        hasFinishedSearch = false
        wasCancelled = false

        let searchID = UUID()
        activeSearchID = searchID
        isSearching = true
        errorMessage = nil
        results = []
        unfilteredResults = []
        rawResults = []
        mergedBookIDs = []
        resultFilter = ""
        resultFilterScope = .all
        totalResultCount = 0
        sourceFailures = []
        failedSourceCount = 0
        sourceCoverage = nil
        hitSourceCount = 0
        checkedSourceCount = 0
        defer {
            if activeSearchID == searchID, searchGeneration == generation {
                isSearching = false
            }
        }

        let imported = appState.sourceStore.sources
        let selectedURL = selectedSourceURL
        let medium = selectedSourceKind
        let (sources, coverage) = await Task.detached(priority: .userInitiated) { () -> ([BookSource], SourceCoverage) in
            let enabled = imported.filter(\.enabled)
            let searchable = enabled.filter(\.hasSearchEntry)
            let candidates = searchable.filter { source in
                if let selectedURL, source.bookSourceUrl != selectedURL { return false }
                return medium.map(source.canSearch(mediaKind:)) ?? true
            }
            return (candidates, SourceCoverage(importedCount: imported.count, enabledCount: enabled.count,
                searchableCount: searchable.count, targetCount: candidates.count))
        }.value
        guard !Task.isCancelled, activeSearchID == searchID, searchGeneration == generation else { return }
        sourceCoverage = coverage
        guard !sources.isEmpty else {
            if selectedSourceURL != nil {
                errorMessage = "所选书源当前不可用或与所选类型不匹配，请重新选择。"
            } else {
                errorMessage = selectedSourceKind.map { "没有启用且支持搜索的\($0.displayName)书源。" }
                    ?? (coverage.enabledCount == 0 ? "没有启用书源，请在书源管理中导入或启用书源。" : "已启用的源没有搜索入口；仅提供分类的源请在「寻书」中打开。")
            }
            return
        }

        let engine = appState.engine
        var hitSources = Set<String>()
        var failures: [String] = []
        var checkedSources = 0
        // Sliding window concurrency respects user configuration (default 12, range 2..32).
        let savedConcurrency = UserDefaults.standard.integer(forKey: "search_concurrent_threads")
        let maxConcurrent = (savedConcurrency >= 2 && savedConcurrency <= 32) ? savedConcurrency : 12
        // Only individual requests time out. A global cutoff silently skipped the rest of a large library.
        var lastPublishAt = Date.distantPast

        func record(_ books: [SearchBook], from source: BookSource) {
            if mergeBooks(books) {
                hitSources.insert(source.bookSourceUrl)
            }
        }

        func publishIfNeeded(force: Bool) async {
            let now = Date()
            if !force, now.timeIntervalSince(lastPublishAt) < 0.4 { return }
            lastPublishAt = now
            hitSourceCount = hitSources.count
            totalResultCount = rawResults.count
            checkedSourceCount = checkedSources
            failedSourceCount = failures.count
            sourceFailures = Array(failures.suffix(40))
            // Filtering and ranking used to run on the main actor for every
            // streamed batch; the row list now renders while it runs elsewhere.
            let snapshot = rawResults
            let exactMatch = matchMode == .exact
            let rankedBooks = await Task.detached(priority: .userInitiated) {
                SearchBookMatcher.filteredAndRanked(snapshot, keyword: keyword, exact: exactMatch)
            }.value
            guard !Task.isCancelled, generation == searchGeneration, activeSearchID == searchID,
                  exactMatch == (matchMode == .exact) else { return }
            await installRankedResults(rankedBooks)
        }

        // Z-Library is merged when it answers; the source phase never waits for
        // it. Its URLSession resource timeout is 60s, which is why a search with
        // only one or two sources felt slower than a search with many.
        let shouldSearchZlib = selectedSourceURL == nil && (selectedSourceKind == nil || selectedSourceKind == .text)
        let zlibSearchTask = Task { () -> [SearchBook] in
            guard shouldSearchZlib else { return [] }
            let res = await ZlibraryEngine.shared.search(keyword: keyword, page: 1)
            if case .success(let b) = res { return b }
            return []
        }
        defer {
            if Task.isCancelled || activeSearchID != searchID { zlibSearchTask.cancel() }
        }

        await withTaskGroup(of: (BookSource, Result<[SearchBook], SourceEngineError>).self) { group in
            var iterator = sources.makeIterator()
            for _ in 0..<maxConcurrent {
                guard let source = iterator.next() else { break }
                group.addTask {
                    (source, await engine.searchBooksWithinListingBudget(source: source, keyword: keyword, page: 1))
                }
            }

            while let outcome = await group.next() {
                let source = outcome.0
                let result = outcome.1
                guard activeSearchID == searchID, searchGeneration == generation, !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                checkedSources += 1
                switch result {
                case .success(let books):
                    record(books, from: source)
                case .failure(let error):
                    failures.append("\(source.bookSourceName): \(error.displayMessage)")
                }
                if let next = iterator.next() {
                    group.addTask {
                        (next, await engine.searchBooksWithinListingBudget(source: next, keyword: keyword, page: 1))
                    }
                }
                await publishIfNeeded(force: false)
            }
        }

        guard activeSearchID == searchID, searchGeneration == generation else { return }
        await publishIfNeeded(force: true)
        guard !Task.isCancelled, activeSearchID == searchID, searchGeneration == generation else { return }
        hasFinishedSearch = true
        // No exact match and a user filter are not engine failures. Only an
        // entirely failed source run takes the error state.
        if rawResults.isEmpty, !failures.isEmpty, failures.count == checkedSourceCount {
            errorMessage = failures.prefix(8).joined(separator: "\n")
        }

        // Merge Z-Library off the critical path: results that arrive after the
        // source phase append to the visible list instead of restarting it.
        let pendingZlib = zlibSearchTask
        Task { @MainActor [weak self] in
            let zlibBooks = await AsyncTimeout.run(seconds: 8) { await pendingZlib.value }
            if zlibBooks == nil {
                pendingZlib.cancel()
            }
            guard let self,
                  let zlibBooks,
                  !zlibBooks.isEmpty,
                  self.activeSearchID == searchID,
                  self.searchGeneration == generation,
                  self.mergeBooks(zlibBooks) else { return }
            self.totalResultCount = self.rawResults.count
            let snapshot = self.rawResults
            let exact = self.matchMode == .exact
            let ranked = await Task.detached(priority: .userInitiated) {
                SearchBookMatcher.filteredAndRanked(snapshot, keyword: keyword, exact: exact)
            }.value
            guard self.activeSearchID == searchID, self.searchGeneration == generation,
                  exact == (self.matchMode == .exact) else { return }
            await self.installRankedResults(ranked)
            guard !Task.isCancelled, self.activeSearchID == searchID, self.searchGeneration == generation else { return }
            self.hasFinishedSearch = true
            if !self.results.isEmpty {
                self.errorMessage = nil
            }
        }
    }

    private func filtered(_ books: [SearchBook], keyword: String) -> [SearchBook] {
        SearchBookMatcher.filteredAndRanked(
            books,
            keyword: keyword,
            exact: matchMode == .exact
        )
    }
}

enum SearchMatchMode: String, CaseIterable, Identifiable {
    case fuzzy
    case exact

    static let initial: Self = .exact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fuzzy: return "模糊"
        case .exact: return "精准"
        }
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


struct ExploreSourceSelectionSheet: View {
    private struct MediaSection: Identifiable {
        let title: String
        let sources: [BookSource]
        var id: String { title }
    }

    @ObservedObject var viewModel: ExploreViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchKeyword = ""

    private var filteredSources: [BookSource] {
        guard !searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return viewModel.availableSources
        }
        let q = searchKeyword.lowercased()
        return viewModel.availableSources.filter {
            $0.bookSourceName.lowercased().contains(q) || ($0.bookSourceGroup?.lowercased().contains(q) == true)
                || $0.mediaCollectionTitle.lowercased().contains(q)
        }
    }

    private var mediaSections: [MediaSection] {
        let groups = Dictionary(grouping: filteredSources) { source in
            if let selected = viewModel.selectedSourceKind, selected != source.sourceKind { return "综合源" }
            return source.mediaCollectionTitle
        }
        return ["小说", "听书", "音乐", "漫画", "视频", "文件", "综合源"].compactMap { title in
            groups[title].map { MediaSection(title: title, sources: $0) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(mediaSections) { section in
                    Section(section.title) {
                        ForEach(section.sources) { source in sourceChoice(source) }
                    }
                }
            }
            .searchable(text: $searchKeyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书源名称或分组")
            .navigationTitle("全部寻书书源 (\(viewModel.availableSources.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func sourceChoice(_ source: BookSource) -> some View {
        let isSelected = viewModel.selectedSource?.id == source.id
        return Button {
            viewModel.selectSource(source)
            dismiss()
        } label: {
            HStack {
                if source.sourceKind.isStreamMedia {
                    Image(systemName: source.isMusicSource ? "music.note" : source.sourceKind.systemImage)
                        .foregroundStyle(AppTheme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.bookSourceName)
                        .font(.headline)
                        .foregroundStyle(isSelected ? AppTheme.accent : .primary)
                    if let group = source.bookSourceGroup?.nilIfEmpty {
                        Text(group)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.accent)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private final class DiscoverVisibilityFlag {
    var isVisible = false
}
