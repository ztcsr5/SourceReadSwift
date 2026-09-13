import SwiftUI
import UIKit

struct DiscoverView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DiscoverViewModel
    @State private var pendingShelfAddBook: SearchBook?
    @State private var showSmartWebReader = false
    @State private var selectedAggregatedBookForSources: AggregatedSearchBook? = nil

    init(viewModel: DiscoverViewModel? = nil) {
        self._viewModel = ObservedObject(wrappedValue: viewModel ?? DiscoverViewModel())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    bookSearchTab

                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.bottom, 22)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .scrollDismissesKeyboard(.interactively)
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
                .submitLabel(.search)
                .onSubmit {
                    viewModel.startSearch()
                }
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { dismissKeyboard() }
                    }
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
            Picker("搜索模式", selection: $viewModel.matchMode) {
                ForEach(SearchMatchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 170)
        }
    }

    private var resultFilterPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.hasUnfilteredResults {
                Picker("筛选范围", selection: $viewModel.resultFilterScope) {
                    ForEach(SearchResultFilterScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                TextField(viewModel.resultFilterScope.placeholder, text: $viewModel.resultFilter)
                    .textInputAutocapitalization(.never)
                    .padding(.horizontal, 12)
                    .frame(height: 42)
                    .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onChange(of: viewModel.resultFilter) { _ in viewModel.applyResultFilter() }
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
            Text("输入书名后，会从启用的小说书源里搜索")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 250)
        } else {
            resultsList
        }
    }

    private var resultsList: some View {
        LazyVStack(spacing: 14) {
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
                    Picker("展示方式", selection: $viewModel.displayMode) {
                        ForEach(SearchDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
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
                    aggregatedBookCard(item)
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
                            searchResultCard(book)
                        }
                    }
                }
            }
        }
    }

    private func aggregatedBookCard(_ item: AggregatedSearchBook) -> some View {
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
                    if !appState.bookshelfStore.contains(item.primaryBook) {
                        pendingShelfAddBook = item.primaryBook
                    }
                } label: {
                    Image(systemName: appState.bookshelfStore.contains(item.primaryBook) ? "checkmark.circle.fill" : "plus.circle")
                        .font(.title2)
                        .foregroundStyle(appState.bookshelfStore.contains(item.primaryBook) ? Color.green : AppTheme.accent)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appState.bookshelfStore.contains(item.primaryBook) ? "已在书架" : "加入书架")

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

    private func searchResultCard(_ book: SearchBook) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink {
                BookDetailView(book: book)
            } label: {
                SearchBookRow(book: book)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if !appState.bookshelfStore.contains(book) {
                    pendingShelfAddBook = book
                }
            } label: {
                Image(systemName: appState.bookshelfStore.contains(book) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title2)
                    .foregroundStyle(appState.bookshelfStore.contains(book) ? Color.green : AppTheme.accent)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appState.bookshelfStore.contains(book) ? "已在书架" : "加入书架")
        }
        .podcastCard()
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
    @Published var results: [SearchBook] = []
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

    var groupedResults: [ResultGroup] {
        Dictionary(grouping: results, by: { $0.sourceUrl.isEmpty ? $0.sourceName : $0.sourceUrl })
            .map { _, books in
                ResultGroup(source: books.first?.sourceName ?? "未知书源", sourceURL: books.first?.sourceUrl ?? "", books: books)
            }
            .sorted {
                if $0.source == $1.source { return $0.id < $1.id }
                return $0.source.localizedStandardCompare($1.source) == .orderedAscending
            }
    }

    var aggregatedResults: [AggregatedSearchBook] {
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

    func bind(appState: AppState) {
        self.appState = appState
    }

    var hasSearchState: Bool {
        isSearching || hasFinishedSearch || wasCancelled || hasRawResults || !results.isEmpty || errorMessage != nil
    }

    func clearSearch() {
        cancelSearch()
        activeKeyword = ""
        hasFinishedSearch = false
        wasCancelled = false
        results = []
        unfilteredResults = []
        rawResults = []
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
        // Search results are already deduplicated by the source search. This only
        // changes the visible projection, so changing the filter never re-runs IO.
        results = SearchResultFilter.apply(unfilteredResults, query: resultFilter, scope: resultFilterScope)
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

        let sources = appState.sourceStore.sources.filter(\.enabled)
        enabledSourceCount = sources.count
        guard !sources.isEmpty else {
            errorMessage = "没有可用书源，请先到书源管理导入书源。"
            return
        }

        let engine = appState.engine
        var allBooks: [SearchBook] = []
        var hitSources = Set<String>()
        var failures: [String] = []

        // 并发执行 Z-Library 全球图书源检索
        let zlibSearchTask = Task { () -> [SearchBook] in
            let res = await ZlibraryEngine.shared.search(keyword: keyword, page: 1)
            if case .success(let b) = res { return b }
            return []
        }

        for batch in sources.chunked(into: 12) {
            guard activeSearchID == searchID, searchGeneration == generation, !Task.isCancelled else { return }
            await withTaskGroup(of: (BookSource, Result<[SearchBook], SourceEngineError>).self) { group in
                for source in batch {
                    group.addTask {
                        let result = await AsyncTimeout.run(seconds: 10) {
                            await engine.searchBooks(source: source, keyword: keyword, page: 1)
                        } ?? .failure(.network("Search timed out"))
                        return (source, result)
                    }
                }

                for await (source, result) in group {
                    guard activeSearchID == searchID, searchGeneration == generation, !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                    checkedSourceCount += 1
                    switch result {
                    case .success(let books):
                        if !books.isEmpty {
                            hitSources.insert(source.bookSourceUrl)
                            allBooks.append(contentsOf: books)
                            rawResults = allBooks
                            totalResultCount = allBooks.count
                            hitSourceCount = hitSources.count
                        }
                    case .failure(let error):
                        let message = "\(source.bookSourceName): \(error.displayMessage)"
                        failures.append(message)
                        sourceFailures = Array(failures.suffix(40))
                    }
                    if checkedSourceCount % 6 == 0 || !allBooks.isEmpty && checkedSourceCount % 3 == 0 {
                        unfilteredResults = filtered(allBooks, keyword: keyword)
                        applyResultFilter()
                        totalResultCount = allBooks.count
                    }
                }
            }
            guard activeSearchID == searchID, searchGeneration == generation, !Task.isCancelled else { return }
            unfilteredResults = filtered(allBooks, keyword: keyword)
            applyResultFilter()
            totalResultCount = allBooks.count
            hitSourceCount = hitSources.count
        }

        // 汇总 Z-Library 检索结果
        let zlibBooks = await zlibSearchTask.value
        if !zlibBooks.isEmpty {
            hitSources.insert("Z-Library")
            allBooks.append(contentsOf: zlibBooks)
            rawResults = allBooks
        }

        guard activeSearchID == searchID, searchGeneration == generation else { return }
        totalResultCount = allBooks.count
        unfilteredResults = filtered(allBooks, keyword: keyword)
        applyResultFilter()
        hitSourceCount = hitSources.count
        hasFinishedSearch = true
        // No exact match and a user filter are not engine failures. Only an
        // entirely failed source run takes the error state.
        if rawResults.isEmpty, failures.count == sources.count {
            errorMessage = failures.prefix(8).joined(separator: "\n")
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
