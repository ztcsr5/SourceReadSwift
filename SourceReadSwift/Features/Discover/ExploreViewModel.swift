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
    @Published var sourceControls: [SourceExploreControl] = []
    @Published var sourceInputs: [String: String] = [:]
    @Published var isLoadingMenu = false
    @Published var sourceActionMessage: String?

    private weak var appState: AppState?
    private var activeTask: Task<Void, Never>?
    /// Guards against a cancelled request clearing the flags of the request that
    /// replaced it, and against a cancelled request leaving `isLoading` stuck.
    private var loadGeneration = 0
    private var menuTask: Task<Void, Never>?
    private var menuGeneration = 0
    private var activeSearchKeyword: String?

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
            cancelSourceLoads()
            selectedSource = nil
            categories = []
            sourceControls = []
            sourceInputs = [:]
            books = []
            selectedCategory = nil
            errorMessage = "该类型暂无配置分类寻书的书源"
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
        cancelSourceLoads()
        selectedSource = source
        selectedCategory = nil
        categories = []
        books = []
        sourceControls = []
        sourceInputs = [:]
        sourceActionMessage = nil
        errorMessage = nil
        guard let engine = appState?.engine else { return }
        isLoadingMenu = true
        let generation = menuGeneration
        menuTask = Task { [weak self] in
            let result = await engine.exploreMenu(source: source)
            guard let self, !Task.isCancelled, self.menuGeneration == generation else { return }
            self.isLoadingMenu = false
            switch result {
            case .success(let menu): self.applyMenu(menu)
            case .failure(let error): self.errorMessage = error.displayMessage
            }
        }
    }

    func performSourceAction(_ control: SourceExploreControl) {
        guard !isLoadingMenu, control.kind == .button,
              sourceControls.contains(control), let source = selectedSource,
              let engine = appState?.engine else { return }
        cancelSourceLoads()
        isLoadingMenu = true
        errorMessage = nil
        sourceActionMessage = nil
        let generation = menuGeneration
        let inputs = sourceInputs
        menuTask = Task { [weak self] in
            let result = await engine.performExploreAction(source: source, action: control.action, inputs: inputs)
            guard let self, !Task.isCancelled, self.menuGeneration == generation else { return }
            self.isLoadingMenu = false
            switch result {
            case .failure(let error): self.errorMessage = error.displayMessage
            case .success(let outcome):
                self.sourceActionMessage = outcome.message
                self.applyMenu(outcome.menu, loadsFirstCategory: outcome.searchKeyword == nil)
                if let keyword = outcome.searchKeyword {
                    self.activeSearchKeyword = keyword
                    self.selectedCategory = nil
                    self.currentPage = 1
                    self.books = []
                    self.canLoadMore = true
                    self.loadBooks(page: 1)
                }
            }
        }
    }

    private func cancelSourceLoads() {
        activeTask?.cancel()
        menuTask?.cancel()
        loadGeneration &+= 1
        menuGeneration &+= 1
        activeSearchKeyword = nil
        isLoading = false
        isLoadingMore = false
        isLoadingMenu = false
    }

    private func applyMenu(_ menu: SourceExploreMenu, loadsFirstCategory: Bool = true) {
        categories = menu.categories
        sourceControls = menu.controls
        sourceInputs = menu.controls.filter { $0.kind == .text }.reduce(into: [:]) {
            $0[$1.title] = sourceInputs[$1.title] ?? $1.defaultValue
        }
        selectedGroup = groups.first
        if loadsFirstCategory, let first = filteredCategories.first ?? categories.first {
            selectCategory(first)
        } else {
            selectedCategory = nil
            books = []
            errorMessage = categories.isEmpty && sourceControls.isEmpty ? "该书源暂无可解析的分类" : nil
        }
    }

    func selectCategory(_ category: ExploreCategory) {
        activeSearchKeyword = nil
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
        let category = selectedCategory
        let keyword = activeSearchKeyword
        guard category != nil || keyword != nil else {
            isLoading = false
            isLoadingMore = false
            errorMessage = categories.isEmpty ? "该书源暂无可解析的分类" : "尚未选择分类，请点一个分类后重试。"
            return
        }
        guard let appState else {
            isLoading = false
            isLoadingMore = false
            errorMessage = "应用尚未就绪，请退出「寻书」后重试。"
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
                if let keyword { return await engine.searchBooks(source: source, keyword: keyword, page: page) }
                return await engine.exploreBooks(source: source, url: category?.url ?? "", page: page)
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
        if activeSearchKeyword != nil { loadBooks(page: 1); return }
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
