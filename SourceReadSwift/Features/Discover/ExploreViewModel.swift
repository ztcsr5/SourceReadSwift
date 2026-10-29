import Foundation
import SwiftUI

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var selectedSource: BookSource?
    @Published var selectedSourceKind: BookSourceKind? = nil
    @Published var selectedCategory: ExploreCategory?
    @Published var selectedGroup: String?
    @Published var categories: [ExploreCategory] = []
    @Published var books: [SearchBook] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var canLoadMore: Bool = true
    @Published var errorMessage: String?
    @Published var currentPage: Int = 1

    private weak var appState: AppState?
    private var activeTask: Task<Void, Never>?
    /// Guards against a cancelled request clearing the flags of the request that
    /// replaced it, and against a cancelled request leaving `isLoading` stuck.
    private var loadGeneration = 0

    func bind(appState: AppState) {
        self.appState = appState
        if selectedSource == nil {
            let available = availableSources
            if let first = available.first {
                selectSource(first)
            }
        }
    }

    var availableSources: [BookSource] {
        guard let appState else { return [] }
        let all = appState.sourceStore.sources.filter { source in
            source.enabled && !(source.exploreUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard let selectedSourceKind else { return all }
        return all.filter { $0.sourceKind == selectedSourceKind }
    }

    func selectSourceKind(_ kind: BookSourceKind?) {
        selectedSourceKind = kind
        if let current = selectedSource, availableSources.contains(where: { $0.id == current.id }) {
            return
        }
        if let first = availableSources.first {
            selectSource(first)
        } else {
            selectedSource = nil
            categories = []
            books = []
            selectedCategory = nil
            errorMessage = "该类型暂无配置分类发现的书源"
        }
    }

    var groups: [String] {
        let set = Set(categories.compactMap(\.group))
        return Array(set).sorted()
    }

    var filteredCategories: [ExploreCategory] {
        guard let selectedGroup, !selectedGroup.isEmpty, selectedGroup != "全部" else {
            return categories
        }
        return categories.filter { $0.group == selectedGroup }
    }

    func selectSource(_ source: BookSource) {
        selectedSource = source
        categories = ExploreCategoryParser.parse(exploreUrl: source.exploreUrl, source: source)
        selectedGroup = groups.first
        if let first = filteredCategories.first ?? categories.first {
            selectCategory(first)
        } else {
            selectedCategory = nil
            books = []
            errorMessage = "该书源暂无可解析的分类"
        }
    }

    func selectCategory(_ category: ExploreCategory) {
        selectedCategory = category
        currentPage = 1
        books = []
        canLoadMore = true
        errorMessage = nil
        loadBooks(page: 1)
    }

    func selectGroup(_ group: String?) {
        selectedGroup = group
        guard let first = filteredCategories.first else {
            books = []
            selectedCategory = nil
            isLoading = false
            isLoadingMore = false
            errorMessage = categories.isEmpty ? "该书源暂无可解析的分类" : "该分组下没有可用分类，请换一个分组"
            return
        }
        selectCategory(first)
    }

    func loadBooks(page: Int) {
        // The in-flight request is retired first, so a leftover task can never
        // blank the flags or the list of the request that replaces it.
        activeTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration

        // Every early exit reports why: a tap used to do nothing at all when one
        // of these was nil.
        guard let source = selectedSource else {
            isLoading = false
            isLoadingMore = false
            errorMessage = "尚未选择书源，请在上方选择一个书源后重试。"
            return
        }
        guard let category = selectedCategory else {
            isLoading = false
            isLoadingMore = false
            errorMessage = categories.isEmpty ? "该书源暂无可解析的分类" : "尚未选择分类，请点一个分类后重试。"
            return
        }
        guard let appState else {
            isLoading = false
            isLoadingMore = false
            errorMessage = "应用尚未就绪，请退出「发现」后重试。"
            return
        }

        if page == 1 {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil

        let engine = appState.engine
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await AsyncTimeout.run(seconds: 12) {
                await engine.exploreBooks(source: source, url: category.url, page: page)
            } ?? .failure(.network("请求超时，已停止加载，请点重试或换个分类"))

            // A superseded request must not touch the state of the newer one,
            // and it must never leave the spinner running.
            guard self.loadGeneration == generation else { return }
            self.isLoading = false
            self.isLoadingMore = false
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let newBooks):
                if page == 1 {
                    self.books = newBooks
                    self.currentPage = 1
                } else {
                    let existingUrls = Set(self.books.map(\.bookUrl))
                    let uniqueNew = newBooks.filter { !existingUrls.contains($0.bookUrl) }
                    self.books.append(contentsOf: uniqueNew)
                    self.currentPage = page
                    if uniqueNew.isEmpty {
                        self.canLoadMore = false
                    }
                }
                if newBooks.isEmpty && page == 1 {
                    self.errorMessage = "暂无相关书籍"
                }
            case .failure(let error):
                if page == 1 {
                    self.errorMessage = error.displayMessage
                } else {
                    // Paging failures stay silent in the footer, but the retry
                    // banner above the list needs a reason.
                    self.canLoadMore = false
                    self.errorMessage = "加载更多失败：\(error.displayMessage)"
                }
            }
        }
    }

    func loadNextPageIfNeeded(currentItem: SearchBook) {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        guard let index = books.firstIndex(where: { $0.id == currentItem.id }) else { return }
        if index >= books.count - 4 {
            loadBooks(page: currentPage + 1)
        }
    }

    func refresh() async {
        // Pull-to-refresh used to do nothing when the category list had failed to
        // parse, so the sheet looked dead. Re-parse, then retry, then explain.
        if let source = selectedSource, categories.isEmpty {
            selectSource(source)
            return
        }
        guard let category = selectedCategory ?? filteredCategories.first else {
            isLoading = false
            isLoadingMore = false
            errorMessage = selectedSource == nil
                ? "尚未选择书源，请在上方选择一个书源后重试。"
                : "该书源暂无可解析的分类"
            return
        }
        selectCategory(category)
    }
}
