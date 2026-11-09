import SwiftUI

/// Searches local destinations and hands an explicit online query to Discover.
struct GlobalSearchView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var bookshelf: BookshelfStore
    @ObservedObject var sources: SourceStore
    let onSearchOnline: (String, String?) -> Void
    /// 作为 tab 呈现时不要抢焦点，避免一进来就弹键盘。
    var autoFocus: Bool = true
    /// 作为 tab 呈现时没有可 dismiss 的容器，交给调用方切回上一个 tab。
    var onClose: (() -> Void)? = nil
    /// tab 形态由系统栏收起/展开承担返回，不显示左上角关闭按钮。
    var showsCloseButton: Bool = true
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var query = ""
    @State private var results: [GlobalSearchEntry] = []
    @State private var catalogRevision = 0
    @State private var catalog: (revision: Int, index: GlobalSearchIndex)?
    @State private var completedSearch: SearchRequest?
    @State private var selectedEntry: GlobalSearchEntry?
    @State private var scope: GlobalSearchIndex.Scope = .all
    @State private var selectedSourceURL: String?

    private struct SearchRequest: Equatable, Sendable {
        let revision: Int?
        let keyword: String
        let scope: String
        let sourceURL: String
    }

    private var searchRequest: SearchRequest {
        SearchRequest(revision: catalog?.revision == catalogRevision ? catalogRevision : nil,
                      keyword: keyword, scope: scope.rawValue,
                      sourceURL: selectedSourceURL ?? "")
    }

    private var selectedSourceName: String? {
        guard let selectedSourceURL else { return nil }
        return sources.sources.first(where: { $0.bookSourceUrl == selectedSourceURL })?.bookSourceName
    }

    private var keyword: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("搜索书籍、作者、摘录、书源或设置", text: $query)
                        .focused($isFocused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { isFocused = false }
                        .accessibilityIdentifier("globalSearch.query")
                        .onChange(of: query) { if $0.count > 200 { query = String($0.prefix(200)) } }
                }
                Section {
                    // 三个入口：按书名 / 按作者 / 限定书源。
                    Picker("搜索范围", selection: $scope) {
                        ForEach(GlobalSearchIndex.Scope.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("globalSearch.scope")
                    if scope == .source {
                        Menu {
                            Button("全部书源") { selectedSourceURL = nil }
                            Divider()
                            ForEach(sources.sources.filter { $0.enabled }) { source in
                                Button {
                                    selectedSourceURL = source.bookSourceUrl
                                } label: {
                                    Label(source.bookSourceName,
                                          systemImage: selectedSourceURL == source.bookSourceUrl ? "checkmark" : "books.vertical")
                                }
                            }
                        } label: {
                            Label(selectedSourceName ?? "选择书源", systemImage: "books.vertical")
                                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        }
                        .accessibilityIdentifier("globalSearch.sourcePicker")
                        if selectedSourceURL == nil {
                            Text("先选择一个书源，再输入关键词。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if keyword.isEmpty {
                    Section("快捷入口") {
                        ForEach(GlobalSearchIndex.settings) { entry in resultLink(entry) }
                    }
                    Text("搜索书架、书签摘录和应用功能，也可以在已启用的书源中联网找书。")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Section {
                        Button {
                            onSearchOnline(keyword, scope == .source ? selectedSourceURL : nil)
                        } label: {
                            Label(scope == .source && selectedSourceName != nil
                                  ? "在「\(selectedSourceName ?? "")」中搜索「\(keyword)」"
                                  : "联网搜索「\(keyword)」", systemImage: "globe")
                        }
                        .accessibilityIdentifier("globalSearch.online")
                        .disabled(scope == .source && selectedSourceURL == nil)
                    }
                    Section("本机结果") {
                        if completedSearch != searchRequest { ProgressView("正在查找").frame(minHeight: 44) }
                        else if results.isEmpty {
                            Text("本机没有匹配项，可以在上方联网搜索。")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(results) { entry in resultLink(entry) }
                            if results.count == 100 {
                                Text("已显示前 100 项，输入更具体的关键词可以缩小范围。")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("全局搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 键盘上的「完成」是收键盘的正规入口：
                // 之前用整块 TapGesture 收键盘，会把手点输入框的那一下也吃掉，导致无法输入。
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { isFocused = false }
                        .accessibilityIdentifier("globalSearch.dismissKeyboard")
                }
                if showsCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") {
                            isFocused = false
                            if let onClose { onClose() } else { dismiss() }
                        }
                        .accessibilityIdentifier("globalSearch.close")
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { selectedEntry != nil },
                set: { if !$0 { selectedEntry = nil } }
            )) {
                if let selectedEntry { destination(selectedEntry) }
            }
            .task { if autoFocus { isFocused = true } }
            .onReceive(bookshelf.$books.dropFirst()) { _ in catalogRevision &+= 1 }
            .onReceive(sources.$sources.dropFirst()) { _ in catalogRevision &+= 1 }
            .task(id: catalogRevision) {
                await rebuildCatalog(revision: catalogRevision)
            }
            .task(id: searchRequest) {
                await runSearch(searchRequest)
            }
        }
        .tint(AppTheme.accent)
    }

    private func rebuildCatalog(revision: Int) async {
        let books = bookshelf.books
        let sourceList = sources.sources
        let worker = Task.detached(priority: .userInitiated) {
            GlobalSearchIndex(entries: GlobalSearchIndex.entries(books: books, sources: sourceList))
        }
        let index = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, catalogRevision == revision else { return }
        catalog = (revision, index)
    }

    private func runSearch(_ request: SearchRequest) async {
        guard !request.keyword.isEmpty, let revision = request.revision,
              let catalog, catalog.revision == revision else { return }
        do { try await Task.sleep(nanoseconds: 150_000_000) }
        catch { return }
        let worker = Task.detached(priority: .userInitiated) {
            catalog.index.search(request.keyword,
                                  scope: GlobalSearchIndex.Scope(rawValue: request.scope) ?? .all,
                                  sourceURL: request.sourceURL.isEmpty ? nil : request.sourceURL)
        }
        let matches = await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
        guard !Task.isCancelled, request == searchRequest else { return }
        results = matches
        completedSearch = request
    }

    private func resultLink(_ entry: GlobalSearchEntry) -> some View {
        Button {
            isFocused = false
            selectedEntry = entry
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(entry.kind)).foregroundStyle(AppTheme.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title).lineLimit(2)
                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("globalSearch.result." + entry.id)
    }

    @ViewBuilder private func destination(_ entry: GlobalSearchEntry) -> some View {
        switch entry.kind {
        case .book:
            if let book = bookshelf.book(id: entry.target) { BookDetailView(book: book.asSearchBook) }
            else { Text("这本书已移出书架，请重新搜索。") }
        case .bookmark:
            if let book = bookshelf.book(id: entry.target),
               let bookmark = book.bookmarks?.first(where: { $0.id == entry.bookmarkID }) {
                BookshelfReaderGatewayView(book: book, initialBookmark: bookmark)
            } else { Text("这条书签已删除，请重新搜索。") }
        case .source: SourceManagerView(initialSearch: entry.target)
        case .setting:
            switch entry.target {
            case "appearance": AppearanceSettingsView()
            case "sources": SourceManagerView()
            case "bookmarks": ReaderBookmarksView()
            default: ReadingHistoryView(store: appState.readingHistoryStore)
            }
        }
    }

    private func symbol(_ kind: GlobalSearchEntry.Kind) -> String {
        switch kind {
        case .book: return "book.closed"
        case .bookmark: return "bookmark"
        case .source: return "network"
        case .setting: return "gearshape"
        }
    }
}
