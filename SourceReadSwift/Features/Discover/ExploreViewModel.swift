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
        categories = ExploreCategoryParser.parse(exploreUrl: source.exploreUrl)
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
        if let first = filteredCategories.first {
            selectCategory(first)
        }
    }

    func loadBooks(page: Int) {
        guard let source = selectedSource, let category = selectedCategory, let appState else { return }
        activeTask?.cancel()

        if page == 1 {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil

        let engine = appState.engine
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await AsyncTimeout.run(seconds: 15) {
                await engine.exploreBooks(source: source, url: category.url, page: page)
            } ?? .failure(.network("请求超时，请检查网络或稍后重试"))

            guard !Task.isCancelled else { return }
            self.isLoading = false
            self.isLoadingMore = false

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
                    self.canLoadMore = false
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
        guard let category = selectedCategory else { return }
        selectCategory(category)
    }
}
