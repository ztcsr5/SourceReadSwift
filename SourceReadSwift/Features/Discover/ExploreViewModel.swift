import Foundation
import SwiftUI

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var selectedSource: BookSource?
    @Published var selectedSourceKind: BookSourceKind? = nil
    @Published var selectedCategory: ExploreCategory?
    @Published var categories: [ExploreCategory] = []
    @Published var books: [SearchBook] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var canLoadMore: Bool = true
    enum Failure {
        case menu(String, ExploreBookmark?)
        case page(Int, String)
    }
    @Published private(set) var failure: Failure?
    @Published var currentPage: Int = 1
    @Published var sourceControls: [SourceExploreControl] = []
    @Published var sourceInputs: [String: String] = [:]
    @Published var isLoadingMenu = false
    @Published var sourceActionMessage: String?
    @Published var browserDestination: SourceLoginDestination?
    @Published private(set) var bookmarks: [ExploreBookmark] = []
    @Published var unavailableBookmark: ExploreBookmark?
    private(set) var selectedBookmark: ExploreBookmark?
    private var preview: [ExploreCategory] = []
    private static let previewCount = 4
    private static let sourceActionTimeout: TimeInterval = 20
    private static let bookmarksKey = "discover.explore.bookmarks.v1"
    private let defaults: UserDefaults

    private weak var appState: AppState?
    private var activeTask: Task<Void, Never>?
    /// Guards against a cancelled request clearing the flags of the request that
    /// replaced it, and against a cancelled request leaving `isLoading` stuck.
    private var loadGeneration = 0
    private var menuTask: Task<Void, Never>?
    private var menuGeneration = 0
    private var activeSearchKeyword: String?
    private var cachedSources: (revision: UInt64, media: BookSourceKind?, sources: [BookSource])?

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func bind(appState: AppState) {
        self.appState = appState
        cachedSources = nil
        reconcileSources()
        if let stored = defaults.data(forKey: Self.bookmarksKey) {
            do { bookmarks = try PropertyListDecoder().decode([ExploreBookmark].self, from: stored) }
            catch { sourceActionMessage = "未能读取本机的常逛栏目。" }
        }
    }

    var availableSources: [BookSource] {
        guard let appState else { return [] }
        let revision = appState.sourceStore.sourcesRevision
        if let cachedSources, cachedSources.revision == revision, cachedSources.media == selectedSourceKind {
            return cachedSources.sources
        }
        let all = appState.sourceStore.sources.filter { source in
            source.enabled && source.exploreUrl?.contains(where: { !$0.isWhitespace }) == true
        }
        let scoped = selectedSourceKind.map { kind in all.filter { $0.canSearch(mediaKind: kind) } } ?? all
        cachedSources = (revision, selectedSourceKind, scoped)
        return scoped
    }

    func selectSourceKind(_ kind: BookSourceKind?) {
        selectedSourceKind = kind
        reconcileSources()
    }

    func reconcileSources() {
        let available = availableSources
        if let current = selectedSource, let updated = available.first(where: { $0.id == current.id }) {
            if updated != current { selectSource(updated) }
            return
        }
        if let first = available.first {
            selectSource(first)
        } else {
            cancelSourceLoads()
            selectedSource = nil
            categories = []
            preview = []
            sourceControls = []
            sourceInputs = [:]
            books = []
            selectedCategory = nil
            selectedBookmark = nil
            unavailableBookmark = nil
            sourceActionMessage = nil
            failure = nil
        }
    }

    var inlineCategories: [ExploreCategory] {
        guard let selectedCategory, !preview.contains(where: { $0.id == selectedCategory.id }) else { return preview }
        return Array(preview.prefix(Self.previewCount - 1)) + [selectedCategory]
    }

    var visibleBookmarks: [ExploreBookmark] { bookmarks.filter { source(for: $0) != nil } }

    func source(for bookmark: ExploreBookmark) -> BookSource? {
        guard let source = appState?.sourceStore.source(for: bookmark.sourceID), source.id == bookmark.sourceID,
              source.enabled, source.exploreUrl?.contains(where: { !$0.isWhitespace }) == true,
              selectedSourceKind.map({ source.canSearch(mediaKind: $0) }) ?? true else { return nil }
        return source
    }

    func toggleBookmark(_ bookmark: ExploreBookmark) {
        var updated = bookmarks.filter { $0 != bookmark }
        if updated.count == bookmarks.count { updated.insert(bookmark, at: 0) }
        do {
            defaults.set(try PropertyListEncoder().encode(updated), forKey: Self.bookmarksKey)
            bookmarks = updated
        } catch {
            sourceActionMessage = "未能保存常逛栏目，请重试。"
        }
    }

    func open(_ bookmark: ExploreBookmark) {
        guard let source = source(for: bookmark) else { return }
        if selectedSource?.id != source.id || isLoadingMenu || categories.isEmpty {
            selectSource(source, opening: bookmark)
        } else if let category = bookmark.resolve(in: categories), category.browserAction == nil {
            if category != selectedCategory { selectCategory(category) }
        } else {
            unavailableBookmark = bookmark
        }
    }

    func selectSource(_ source: BookSource, opening bookmark: ExploreBookmark? = nil) {
        cancelSourceLoads()
        selectedSource = source
        selectedCategory = nil
        selectedBookmark = nil
        unavailableBookmark = nil
        categories = []
        preview = []
        books = []
        sourceControls = []
        sourceInputs = [:]
        sourceActionMessage = nil
        failure = nil
        guard let engine = appState?.engine else { return }
        isLoadingMenu = true
        let generation = menuGeneration
        menuTask = Task { [weak self] in
            let result = await engine.exploreMenu(source: source)
            guard let self, !Task.isCancelled, self.menuGeneration == generation else { return }
            self.isLoadingMenu = false
            switch result {
            case .success(let menu): self.applyMenu(menu, opening: bookmark)
            case .failure(let error): self.failure = .menu(error.displayMessage, bookmark)
            }
        }
    }

    func performSourceAction(_ control: SourceExploreControl) {
        guard control.kind == .button || control.kind == .select, sourceControls.contains(control) else { return }
        runSourceAction(control.action)
    }

    private func runSourceAction(_ action: String) {
        guard !isLoadingMenu, let source = selectedSource, let engine = appState?.engine else { return }
        isLoadingMenu = true
        sourceActionMessage = nil
        let generation = menuGeneration
        let inputs = sourceInputs
        let timeout = Self.sourceActionTimeout
        menuTask = Task { [weak self] in
            let result = await AsyncTimeout.run(seconds: timeout) {
                await engine.performExploreAction(source: source, action: action, inputs: inputs)
            } ?? .failure(.network("书源操作超时，请稍后重试"))
            guard let self, !Task.isCancelled, self.menuGeneration == generation else { return }
            self.isLoadingMenu = false
            switch result {
            case .failure(let error): self.sourceActionMessage = error.displayMessage
            case .success(let outcome):
                self.sourceActionMessage = outcome.message
                if let destination = outcome.destination {
                    self.browserDestination = destination
                    return
                }
                if let menu = outcome.menu { self.applyMenu(menu, loadsFirstCategory: outcome.searchKeyword == nil) }
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
        browserDestination = nil
        isLoading = false
        isLoadingMore = false
        isLoadingMenu = false
    }

    private func applyMenu(_ menu: SourceExploreMenu, opening bookmark: ExploreBookmark? = nil, loadsFirstCategory: Bool = true) {
        activeSearchKeyword = nil
        var seen = Set<String>()
        categories = menu.categories.filter { seen.insert($0.id).inserted }
        // Give each group a turn on the index before filling the remaining spaces in source order.
        var groups = Set<String?>()
        var sample: [ExploreCategory] = []
        for item in categories {
            if groups.insert(item.group).inserted { sample.append(item) }
            if sample.count == Self.previewCount { break }
        }
        if sample.count < Self.previewCount {
            for item in categories.prefix(Self.previewCount) where !sample.contains(item) {
                sample.append(item)
                if sample.count == Self.previewCount { break }
            }
        }
        preview = sample
        sourceControls = menu.controls
        sourceInputs = menu.controls.filter { $0.kind == .text || $0.kind == .select }.reduce(into: [:]) {
            $0[$1.title] = sourceInputs[$1.title] ?? $1.defaultValue
        }
        failure = nil
        if let bookmark {
            if let category = bookmark.resolve(in: categories), category.browserAction == nil { selectCategory(category) }
            else { unavailableBookmark = bookmark }
        } else if loadsFirstCategory, let first = categories.first(where: { $0.browserAction == nil }) {
            selectCategory(first)
        } else {
            activeTask?.cancel()
            loadGeneration &+= 1
            isLoading = false
            isLoadingMore = false
            selectedCategory = nil
            selectedBookmark = nil
            books = []
            if sourceActionMessage == nil { sourceActionMessage = menu.message }
        }
    }

    func selectCategory(_ category: ExploreCategory) {
        guard !isLoadingMenu, let source = selectedSource, categories.contains(category) else { return }
        if let action = category.browserAction {
            runSourceAction(action)
            return
        }
        activeSearchKeyword = nil
        selectedCategory = category
        let existing = bookmarks.first { $0.sourceID == source.id && $0.title == category.title && $0.resolve(in: categories) == category }
        selectedBookmark = existing ?? ExploreBookmark(sourceID: source.id, category: category, in: categories)
        currentPage = 1
        books = []
        canLoadMore = true
        loadBooks(page: 1)
    }

    func reloadAfterSourceLogin() {
        guard let source = selectedSource else { return }
        selectSource(source)
    }

    var listingTitle: String? { selectedCategory?.title ?? activeSearchKeyword }

    func retry() {
        switch failure {
        case .menu(_, let bookmark):
            if let source = selectedSource { selectSource(source, opening: bookmark) }
        case .page(let page, _): loadBooks(page: page)
        case nil: break
        }
    }

    private func loadBooks(page: Int) {
        // The in-flight request is retired first, so a leftover task can never
        // blank the flags or the list of the request that replaces it.
        activeTask?.cancel()
        loadGeneration &+= 1
        let generation = loadGeneration

        guard let source = selectedSource, let appState else { return }
        let category = selectedCategory
        let keyword = activeSearchKeyword
        guard category != nil || keyword != nil else { return }

        isLoading = page == 1
        isLoadingMore = page > 1
        failure = nil

        let engine = appState.engine
        let categoryURL = category?.url ?? ""
        let seconds = keyword == nil ? SourceListingBudget.explore(for: source, url: categoryURL)
            : SourceListingBudget.search(for: source)
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await AsyncTimeout.run(seconds: seconds) {
                if let keyword { return await engine.searchBooks(source: source, keyword: keyword, page: page) }
                return await engine.exploreBooks(source: source, url: categoryURL, page: page)
            } ?? .failure(.network("加载超时（超过 \(Int(seconds)) 秒），请点重试或换个分类"))

            // A superseded request must not touch the state of the newer one,
            // and it must never leave the spinner running.
            guard self.loadGeneration == generation else { return }
            self.isLoading = false
            self.isLoadingMore = false
            guard !Task.isCancelled else { return }

            switch result {
            case .success(let newBooks):
                var seen = page == 1 ? Set<String>() : Set(self.books.map(\.id))
                let additions = newBooks.filter { seen.insert($0.id).inserted }
                if page == 1 { self.books = additions } else { self.books.append(contentsOf: additions) }
                self.currentPage = page
                self.canLoadMore = !additions.isEmpty
            case .failure(let error):
                self.failure = .page(page, error.displayMessage)
            }
        }
    }

    func loadNextPage() {
        guard canLoadMore, !books.isEmpty, failure == nil, !isLoadingMenu, !isLoading, !isLoadingMore else { return }
        loadBooks(page: currentPage + 1)
    }

    func refresh() async {
        if !isLoadingMenu, case .menu = failure {
            retry()
        } else if !isLoadingMenu, listingTitle != nil {
            loadBooks(page: 1)
        } else if !isLoadingMenu, let source = selectedSource {
            selectSource(source)
        }
        await menuTask?.value
        await activeTask?.value
    }
}
