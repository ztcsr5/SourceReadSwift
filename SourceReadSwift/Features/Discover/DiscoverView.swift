import SwiftUI
import UIKit

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DiscoverViewModel
    @StateObject private var exploreViewModel = ExploreViewModel()
    @State private var selectedTab: DiscoverTab = .search
    @State private var pendingShelfAddBook: SearchBook?
    @State private var showSmartWebReader = false
    @State private var showExploreSourcePickerSheet = false
    @State private var selectedAggregatedBookForSources: AggregatedSearchBook? = nil
    @State private var detectedClipboardSourceURL: String? = nil
    @State private var lastCheckedPasteboardChangeCount: Int = -1
    @State private var isImportingClipboardSource = false
    @State private var clipboardImportToast: String? = nil
    @AppStorage("discover_search_history") private var searchHistoryJSON: String = "[]"
    /// Cached decode of `searchHistoryJSON`. Decoding inside `body` ran a full
    /// JSON decode (and two array copies) on every layout pass of the search tab,
    /// including every streaming update during a search.
    @State private var cachedSearchHistory: [String] = []

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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        cachedSearchHistory = []
        searchHistoryJSON = "[]"
    }

    enum DiscoverTab: String, CaseIterable, Identifiable {
        case search = "全网搜索"
        case explore = "分类发现"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .search: return "magnifyingglass"
            case .explore: return "safari"
            }
        }
    }

    init(viewModel: DiscoverViewModel? = nil) {
        self._viewModel = ObservedObject(wrappedValue: viewModel ?? DiscoverViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if detectedClipboardSourceURL != nil {
                        clipboardSourceBanner
                    }

                    HStack(spacing: 0) {
                        ForEach(DiscoverTab.allCases) { tab in
                            let isSelected = selectedTab == tab
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedTab = tab
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: tab.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text(tab.rawValue)
                                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                                }
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background {
                                    if isSelected {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(AppTheme.accent)
                                            .shadow(color: AppTheme.accent.opacity(0.24), radius: 3, y: 1)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                    mediumFilterPillBar

                    if selectedTab == .search {
                        bookSearchTab
                    } else {
                        bookExploreTab
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 22)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                if selectedTab == .explore {
                    await exploreViewModel.refresh()
                }
            }
            .pageBackground()
            .navigationTitle("发现")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showSmartWebReader = true
                    } label: {
                        Image(systemName: "safari")
                    }
                    .accessibilityLabel("智能网页阅读")
                }
            }
            .task {
                viewModel.bind(appState: appState)
                exploreViewModel.bind(appState: appState)
                if cachedSearchHistory.isEmpty {
                    cachedSearchHistory = Self.decodeSearchHistory(searchHistoryJSON)
                }
                checkClipboard()
            }
            .onChange(of: searchHistoryJSON) { value in
                let decoded = Self.decodeSearchHistory(value)
                if decoded != cachedSearchHistory {
                    cachedSearchHistory = decoded
                }
            }
            .onAppear {
                checkClipboard()
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
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    appState.bookshelfStore.addOrUpdate(book)
                    pendingShelfAddBook = nil
                }
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
                                            if let latest = sourceBook.lastChapter {
                                                Text(latest)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Text(sourceBook.bookUrl)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } header: {
                            Text("共 \(aggregated.sources.count) 个书源提供《\(aggregated.name)》")
                        }
                    }
                    .navigationTitle("选择书源")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    private var currentSourceKind: BookSourceKind? {
        selectedTab == .search ? viewModel.selectedSourceKind : exploreViewModel.selectedSourceKind
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
            .padding(.vertical, 2)
        }
    }

    private func setMediumFilter(_ kind: BookSourceKind?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if selectedTab == .search {
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
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(isSelected ? AppTheme.accent : Color(UIColor.secondarySystemGroupedBackground), in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .overlay {
                if !isSelected {
                    Capsule().stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var bookSearchTab: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(spacing: 14) {
                searchField
                matchModePicker
                resultFilterPicker
            }
            .onChange(of: viewModel.matchMode) { _ in
                viewModel.applyMatchMode()
            }

            Text("搜索结果")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            content
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("搜索书名或作者", text: $viewModel.keyword)
                .font(.system(size: 16, weight: .semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit {
                    saveSearchKeyword(viewModel.keyword)
                    viewModel.startSearch()
                }

            if !viewModel.keyword.isEmpty {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .background(Color(.systemGray5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onChange(of: viewModel.keyword) { value in
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               viewModel.hasSearchState {
                viewModel.clearSearch()
            }
        }
    }

    private var matchModePicker: some View {
        HStack {
            Spacer()
            HStack(spacing: 0) {
                ForEach(SearchMatchMode.allCases) { mode in
                    let isSelected = viewModel.matchMode == mode
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.matchMode = mode
                    } label: {
                        Text(mode.title)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(AppTheme.accent)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var resultFilterPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasUnfilteredResults {
                HStack(spacing: 0) {
                    ForEach(SearchResultFilterScope.allCases) { scope in
                        let isSelected = viewModel.resultFilterScope == scope
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            viewModel.resultFilterScope = scope
                        } label: {
                            Text(scope.title)
                                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                                .padding(.horizontal, 10)
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

                TextField(viewModel.resultFilterScope.placeholder, text: $viewModel.resultFilter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: viewModel.resultFilter) { _ in viewModel.applyResultFilterDebounced() }
                    .onChange(of: viewModel.resultFilterScope) { _ in viewModel.applyResultFilter() }
            }
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
        } else if viewModel.hasUnfilteredResults && viewModel.results.isEmpty {
            EmptyStateCard(systemImage: "line.3.horizontal.decrease.circle", title: "没有符合筛选的结果", message: "换一个筛选词，或切换书名、作者、来源范围。")
        } else if viewModel.results.isEmpty, viewModel.hasFinishedSearch {
            EmptyStateCard(systemImage: "magnifyingglass", title: viewModel.hasRawResults ? "没有精准匹配" : "没有搜索结果", message: viewModel.hasRawResults ? "书源已返回候选书籍，切换模糊模式可查看相关结果。" : "书源已完成搜索，尝试更换关键词或书源。")
        } else if viewModel.results.isEmpty, viewModel.wasCancelled {
            EmptyStateCard(systemImage: "pause.circle", title: "搜索已取消", message: "再次提交关键词可以重新搜索。")
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
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
        BookshelfMembership(store: appState.bookshelfStore)
    }

    @MainActor
    private struct BookshelfMembership {
        private let ids: Set<String>
        private let localBookURLs: Set<String>

        init(store: BookshelfStore) {
            let books = store.books
            ids = Set(books.map(\.id))
            localBookURLs = Set(books.map(\.bookURL))
        }

        func contains(_ book: SearchBook) -> Bool {
            if ids.contains(book.id) { return true }
            guard book.sourceUrl.hasPrefix("local://") else { return false }
            return localBookURLs.contains(book.bookUrl)
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

                HStack {
                    Text(viewModel.displayMode == .aggregated
                        ? "聚合为 \(viewModel.aggregatedResults.count) 部书籍"
                        : "按书源分组显示")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(SearchDisplayMode.allCases) { mode in
                            let isSelected = viewModel.displayMode == mode
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
            }

            if !viewModel.sourceFailures.isEmpty {
                DisclosureGroup("有 \(viewModel.sourceFailures.count) 个源未返回结果") {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(viewModel.sourceFailures, id: \.self) { failure in
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

            if viewModel.displayMode == .aggregated {
                ForEach(viewModel.aggregatedResults) { item in
                    aggregatedBookCard(item, inShelf: shelf.contains(item.primaryBook))
                }
            } else {
                ForEach(viewModel.groupedResults) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "books.vertical")
                            Text(group.source)
                                .font(.subheadline.weight(.bold))
                            Text("\(group.books.count) 条")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(AppTheme.accent)
                        ForEach(group.books) { book in
                            searchResultCard(book, inShelf: shelf.contains(book))
                        }
                    }
                }
            }
        }
    }

    private func aggregatedBookCard(_ item: AggregatedSearchBook, inShelf: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            NavigationLink {
                BookDetailView(book: item.primaryBook, availableSources: item.sources)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    aggregatedCover(item.coverUrl)

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
                                .lineLimit(2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if !inShelf {
                        pendingShelfAddBook = item.primaryBook
                    }
                } label: {
                    Image(systemName: inShelf ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .foregroundStyle(inShelf ? Color.green : AppTheme.accent)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(inShelf ? "已在书架" : "加入书架")

                if item.sourceCount > 1 {
                    Button {
                        selectedAggregatedBookForSources = item
                    } label: {
                        Text("换源")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.systemGray5), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .podcastCard()
    }

    @ViewBuilder
    private func aggregatedCover(_ coverUrl: String?) -> some View {
        if let coverUrl, let url = URL(string: coverUrl) {
            CachedRemoteImage(url: url) {
                aggregatedCoverPlaceholder
            }
            .frame(width: 74, height: 98)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            aggregatedCoverPlaceholder
                .frame(width: 74, height: 98)
        }
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
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                .background(AppTheme.accent, in: Capsule())
                .foregroundStyle(.white)

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
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                        ?? "当前启用的书源中未配置分类发现规则(exploreUrl)。您可以在书源管理中导入更多精品书源。"
                )
            } else {
                sourceSelectorSection

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
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            exploreViewModel.selectSource(source)
                        } label: {
                            HStack(spacing: 4) {
                                if source.bookSourceType == 1 {
                                    Image(systemName: "headphones")
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
            .accessibilityLabel("展开全部发现书源列表")
        }
        .sheet(isPresented: $showExploreSourcePickerSheet) {
            ExploreSourceSelectionSheet(viewModel: exploreViewModel)
        }
    }

    private var categorySelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if exploreViewModel.groups.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(exploreViewModel.groups, id: \.self) { grp in
                            let isSelected = exploreViewModel.selectedGroup == grp
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                exploreViewModel.selectGroup(grp)
                            } label: {
                                Text(grp)
                                    .font(.caption.weight(isSelected ? .bold : .regular))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                                    .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(exploreViewModel.filteredCategories) { cat in
                        let isSelected = exploreViewModel.selectedCategory?.id == cat.id
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            exploreViewModel.selectCategory(cat)
                        } label: {
                            Text(cat.title)
                                .font(.footnote.weight(isSelected ? .semibold : .regular))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    isSelected ? Color.primary.opacity(0.12) : Color(UIColor.tertiarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .foregroundStyle(isSelected ? Color.primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
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

struct AggregatedSearchBook: Identifiable {
    var id: String { "\(name.lowercased())|\(author?.lowercased() ?? "")" }
    let name: String
    let author: String?
    let coverUrl: String?
    let intro: String?
    let latestChapter: String?
    let sources: [SearchBook]

    var sourceCount: Int { sources.count }
    var primaryBook: SearchBook { sources.first! }
}

@MainActor
final class DiscoverViewModel: ObservableObject {
    @Published var keyword = ""
    @Published var displayMode: SearchDisplayMode = .aggregated
    @Published var matchMode: SearchMatchMode = .exact
    @Published var resultFilterScope: SearchResultFilterScope = .all
    @Published var resultFilter = ""
    @Published var selectedSourceKind: BookSourceKind? = nil
    /// Visible, filtered result rows. `didSet` refreshes the derived groupings
    /// once per change; the groupings used to be recomputed on every `body`
    /// read, which is what dropped frames while results streamed in.
    @Published var results: [SearchBook] = [] {
        didSet { rebuildDerivedResults() }
    }
    @Published private(set) var groupedResults: [ResultGroup] = []
    @Published private(set) var aggregatedResults: [AggregatedSearchBook] = []
    private var unfilteredResults: [SearchBook] = []
    var hasUnfilteredResults: Bool { !unfilteredResults.isEmpty }
    var hasRawResults: Bool { !rawResults.isEmpty }
    @Published private(set) var hasFinishedSearch = false
    @Published private(set) var wasCancelled = false
    var filterSummary: String {
        resultFilter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " · 筛选后 \(results.count) 条"
    }
    @Published var isSearching = false
    @Published var errorMessage: String?
    @Published var hitSourceCount = 0
    @Published var checkedSourceCount = 0
    @Published var totalResultCount = 0
    @Published var sourceFailures: [String] = []
    @Published private(set) var enabledSourceCount = 0

    struct ResultGroup: Identifiable {
        let source: String
        let sourceURL: String
        let books: [SearchBook]
        var id: String { sourceURL.isEmpty ? source : sourceURL }
    }

    /// Recomputed only when `results` changes, never per layout pass.
    private func rebuildDerivedResults() {
        groupedResults = Self.makeGroupedResults(from: results)
        aggregatedResults = Self.makeAggregatedResults(from: results)
    }

    private static func makeGroupedResults(from results: [SearchBook]) -> [ResultGroup] {
        Dictionary(grouping: results, by: { $0.sourceUrl.isEmpty ? $0.sourceName : $0.sourceUrl })
            .map { _, books in
                ResultGroup(source: books.first?.sourceName ?? "未知书源", sourceURL: books.first?.sourceUrl ?? "", books: books)
            }
            .sorted {
                if $0.source == $1.source { return $0.id < $1.id }
                return $0.source.localizedStandardCompare($1.source) == .orderedAscending
            }
    }

    private static func makeAggregatedResults(from results: [SearchBook]) -> [AggregatedSearchBook] {
        var groups: [String: [SearchBook]] = [:]
        var orderedKeys: [String] = []

        for book in results {
            let cleanName = book.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanAuthor = (book.author ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(cleanName.lowercased())|\(cleanAuthor.lowercased())"

            if groups[key] == nil {
                groups[key] = []
                orderedKeys.append(key)
            }
            if !groups[key]!.contains(where: { $0.sourceUrl == book.sourceUrl && $0.bookUrl == book.bookUrl }) {
                groups[key]!.append(book)
            }
        }

        return orderedKeys.compactMap { key -> AggregatedSearchBook? in
            guard let list = groups[key], !list.isEmpty else { return nil }
            let bestBook = list.first(where: { !($0.coverUrl ?? "").isEmpty && !($0.intro ?? "").isEmpty })
                ?? list.first(where: { !($0.coverUrl ?? "").isEmpty })
                ?? list[0]

            let bestLatest = list.compactMap(\.lastChapter).first(where: { !$0.isEmpty })
            let bestIntro = list.compactMap(\.intro).first(where: { !$0.isEmpty })
            let bestCover = list.compactMap(\.coverUrl).first(where: { !$0.isEmpty })

            return AggregatedSearchBook(
                name: bestBook.name,
                author: bestBook.author,
                coverUrl: bestCover,
                intro: bestIntro,
                latestChapter: bestLatest,
                sources: list
            )
        }
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
        enabledSourceCount = 0
        lastSubmittedKeyword = ""
        errorMessage = nil
        resultFilter = ""
        resultFilterScope = .all
        // Set the text last so the view's empty-keyword observer sees an
        // already-reset model and cannot recursively trigger another reset.
        keyword = ""
    }

    func cancelSearch() {
        wasCancelled = isSearching
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
        var base = unfilteredResults
        if let kind = selectedSourceKind {
            base = base.filter { book in
                sourceKind(for: book) == kind
            }
        }
        results = SearchResultFilter.apply(base, query: resultFilter, scope: resultFilterScope)
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
        let sources = appState?.sourceStore.sources ?? []
        let token = "\(sources.count)|\(sources.first?.bookSourceUrl ?? "")|\(sources.last?.bookSourceUrl ?? "")"
        if token != sourceKindCacheToken {
            var map: [String: BookSourceKind] = [:]
            map.reserveCapacity(sources.count)
            for source in sources {
                map[source.bookSourceUrl] = source.sourceKind
            }
            sourceKindCache = map
            sourceKindCacheToken = token
        }
        return sourceKindCache[book.sourceUrl] ?? .text
    }

    func selectSourceKind(_ kind: BookSourceKind?) {
        guard selectedSourceKind != kind else { return }
        selectedSourceKind = kind
        applyResultFilter()
        if !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastSubmittedKeyword = ""
            startSearch()
        }
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
            enabledSourceCount = 0
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
        hitSourceCount = 0
        checkedSourceCount = 0
        defer {
            if activeSearchID == searchID, searchGeneration == generation {
                isSearching = false
            }
        }

        let sources = appState.sourceStore.sources.filter { source in
            guard source.enabled else { return false }
            if let kind = selectedSourceKind {
                return source.sourceKind == kind
            }
            return true
        }
        enabledSourceCount = sources.count
        guard !sources.isEmpty else {
            errorMessage = selectedSourceKind != nil ? "未找到启用的\(selectedSourceKind!.displayName)书源，请在书源管理中导入或启用相应源。" : "没有可用书源，请先到书源管理导入书源。"
            return
        }

        let engine = appState.engine
        var hitSources = Set<String>()
        var failures: [String] = []
        // A fixed batch of 12 made every batch wait for its slowest source, so
        // 17 batches could serialise up to 17 × 10s. A sliding window keeps the
        // same 12 requests in flight and publishes each answer immediately.
        let maxConcurrent = 12
        // Per-source timeouts still bound each request; this bounds the whole run.
        let overallDeadline = Date().addingTimeInterval(20)
        var lastPublishAt = Date.distantPast

        func record(_ books: [SearchBook], from source: BookSource) {
            if mergeBooks(books) {
                hitSources.insert(source.bookSourceUrl)
            }
        }

        func publishIfNeeded(force: Bool) async {
            let now = Date()
            if !force, now.timeIntervalSince(lastPublishAt) < 0.2 { return }
            lastPublishAt = now
            hitSourceCount = hitSources.count
            totalResultCount = rawResults.count
            // Filtering and ranking used to run on the main actor for every
            // streamed batch; the row list now renders while it runs elsewhere.
            let snapshot = rawResults
            let exactMatch = matchMode == .exact
            let rankedBooks = await Task.detached(priority: .userInitiated) {
                SearchBookMatcher.filteredAndRanked(snapshot, keyword: keyword, exact: exactMatch)
            }.value
            unfilteredResults = rankedBooks
            applyResultFilter()
        }

        // Z-Library is merged when it answers; the source phase never waits for
        // it. Its URLSession resource timeout is 60s, which is why a search with
        // only one or two sources felt slower than a search with many.
        let shouldSearchZlib = selectedSourceKind == nil || selectedSourceKind == .text
        let zlibSearchTask = Task { () -> [SearchBook] in
            guard shouldSearchZlib else { return [] }
            let res = await ZlibraryEngine.shared.search(keyword: keyword, page: 1)
            if case .success(let b) = res { return b }
            return []
        }

        await withTaskGroup(of: (BookSource, Result<[SearchBook], SourceEngineError>).self) { group in
            var iterator = sources.makeIterator()
            var inFlight = 0
            while inFlight < maxConcurrent, let source = iterator.next() {
                group.addTask {
                    let result = await AsyncTimeout.run(seconds: 10) {
                        await engine.searchBooks(source: source, keyword: keyword, page: 1)
                    } ?? .failure(.network("Search timed out"))
                    return (source, result)
                }
                inFlight += 1
            }

            while let outcome = await group.next() {
                let source = outcome.0
                let result = outcome.1
                inFlight -= 1
                guard activeSearchID == searchID, searchGeneration == generation, !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
                checkedSourceCount += 1
                switch result {
                case .success(let books):
                    record(books, from: source)
                case .failure(let error):
                    failures.append("\(source.bookSourceName): \(error.displayMessage)")
                    sourceFailures = Array(failures.suffix(40))
                }
                await publishIfNeeded(force: false)

                if Date() < overallDeadline, let next = iterator.next() {
                    group.addTask {
                        let result = await AsyncTimeout.run(seconds: 10) {
                            await engine.searchBooks(source: next, keyword: keyword, page: 1)
                        } ?? .failure(.network("Search timed out"))
                        return (next, result)
                    }
                    inFlight += 1
                }
            }
        }

        guard activeSearchID == searchID, searchGeneration == generation else { return }
        await publishIfNeeded(force: true)
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
            self.hitSourceCount += 1
            self.totalResultCount = self.rawResults.count
            self.unfilteredResults = self.filtered(self.rawResults, keyword: keyword)
            self.applyResultFilter()
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
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSources) { source in
                    let isSelected = viewModel.selectedSource?.id == source.id
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.selectSource(source)
                        dismiss()
                    } label: {
                        HStack {
                            if source.bookSourceType == 1 {
                                Image(systemName: "headphones")
                                    .foregroundStyle(AppTheme.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.bookSourceName)
                                    .font(.headline)
                                    .foregroundStyle(isSelected ? AppTheme.accent : .primary)
                                if let grp = source.bookSourceGroup, !grp.isEmpty {
                                    Text(grp)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(AppTheme.accent)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchKeyword, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索书源名称或分组")
            .navigationTitle("全部发现书源 (\(viewModel.availableSources.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
