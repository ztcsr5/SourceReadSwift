import Foundation

/// Searchable local destinations contain metadata only, never whole chapter bodies.
struct GlobalSearchEntry: Identifiable, Sendable, Equatable {
    enum Kind: String, Sendable { case book, bookmark, source, setting }
    let id: String
    let kind: Kind
    let title: String
    let subtitle: String
    let target: String
    var bookmarkID: String? = nil
    /// Empty for settings entries; otherwise the exact book source that owns
    /// this row, so the source-scoped search is a real filter rather than a
    /// subtitle guess.
    var sourceURL: String = ""
    /// Author is its own scope: the subtitle also carries group and synopsis
    /// text, so matching it here made "按作者" behave like a global search.
    var author: String = ""
}

struct GlobalSearchIndex: Sendable {
    private struct IndexedEntry: Sendable {
        let destination: GlobalSearchEntry
        let title: String
        let searchable: String
    }
    private let indexedEntries: [IndexedEntry]

    init(entries: [GlobalSearchEntry]) {
        var indexed: [IndexedEntry] = []
        indexed.reserveCapacity(entries.count)
        for entry in entries {
            guard !Task.isCancelled else { break }
            let title = Self.normalize(entry.title)
            indexed.append(IndexedEntry(destination: entry, title: title,
                searchable: title + " " + Self.normalize(entry.subtitle)))
        }
        indexedEntries = indexed
    }

    static let settings: [GlobalSearchEntry] = [
        .init(id: "settings.appearance", kind: .setting, title: "主题与外观", subtitle: "颜色 布局 动效 深色模式", target: "appearance"),
        .init(id: "settings.sources", kind: .setting, title: "书源管理", subtitle: "导入 登录 规则 检测", target: "sources"),
        .init(id: "settings.bookmarks", kind: .setting, title: "书签与摘录", subtitle: "阅读笔记 书摘 收藏", target: "bookmarks"),
        .init(id: "settings.history", kind: .setting, title: "阅读历史", subtitle: "最近阅读 记录", target: "history")
    ]

    /// Builds a value-only catalog suitable for the background search task.
    static func entries(books: [BookshelfBook], sources: [BookSource]) -> [GlobalSearchEntry] {
        var entries = settings
        for book in books {
            guard !Task.isCancelled else { return [] }
            entries.append(.init(id: "book:" + book.id, kind: .book, title: book.title,
                subtitle: [book.author, book.groupName, book.intro].compactMap { $0 }.joined(separator: " · "),
                target: book.id, sourceURL: book.sourceURL, author: book.author))
            for bookmark in book.bookmarks ?? [] {
                guard !Task.isCancelled else { return [] }
                entries.append(.init(id: "bookmark:" + book.id + ":" + bookmark.id, kind: .bookmark,
                    title: bookmark.chapterTitle, subtitle: book.title + " · " + bookmark.snippet,
                    target: book.id, bookmarkID: bookmark.id, sourceURL: book.sourceURL, author: book.author))
            }
        }
        for source in sources {
            guard !Task.isCancelled else { return [] }
            entries.append(.init(id: "source:" + source.id, kind: .source, title: source.bookSourceName,
                                 subtitle: source.bookSourceGroup ?? "书源", target: source.bookSourceName,
                                 sourceURL: source.bookSourceUrl))
        }
        return entries
    }

    /// Matches every query token, ranks titles first and bounds the rendered result count.
    static func search(_ query: String, entries: [GlobalSearchEntry], limit: Int = 100) -> [GlobalSearchEntry] {
        guard !Task.isCancelled else { return [] }
        return Self(entries: entries).search(query, limit: limit)
    }

    /// 搜索范围：全部 / 只按书名 / 只按作者 / 只在该书源内。
    enum Scope: String, CaseIterable, Sendable, Identifiable {
        case all, title, author, source
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "全部"
            case .title: return "书名"
            case .author: return "作者"
            case .source: return "书源"
            }
        }
    }

    /// 在指定范围里搜索；范围过滤在打分之前完成，排序规则与全量搜索一致。
    func search(_ query: String, scope: Scope, limit: Int = 100,
                sourceURL: String? = nil) -> [GlobalSearchEntry] {
        guard limit > 0 else { return [] }
        let tokens = Self.normalize(String(query.prefix(200))).split(whereSeparator: \.isWhitespace).map(String.init)

        // Source scope means "inside this source", not "subtitle mentions a
        // source". Without a concrete source there is nothing to search.
        if scope == .source {
            guard let sourceURL, !sourceURL.isEmpty else { return [] }
            let candidates = indexedEntries.filter { $0.destination.sourceURL == sourceURL }
            if tokens.isEmpty {
                return Task.isCancelled ? [] : candidates.prefix(limit).map(\.destination)
            }
            var matches: [(GlobalSearchEntry, Int)] = []
            for entry in candidates {
                guard !Task.isCancelled else { return [] }
                guard tokens.allSatisfy({ entry.searchable.contains($0) }) else { continue }
                let score = tokens.reduce(0) { $0 + (entry.title.hasPrefix($1) ? 4 : entry.title.contains($1) ? 2 : 0) }
                matches.append((entry.destination, score))
            }
            matches.sort {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.id < $1.0.id
            }
            return Task.isCancelled ? [] : matches.prefix(limit).map(\.0)
        }

        guard scope != .all else { return search(query, limit: limit) }
        guard !tokens.isEmpty else { return [] }
        var matches: [(GlobalSearchEntry, Int)] = []
        for entry in indexedEntries {
            guard !Task.isCancelled else { return [] }
            let haystack: String
            switch scope {
            case .title: haystack = entry.title
            case .author: haystack = Self.normalize(entry.destination.author)
            case .source, .all: haystack = entry.searchable
            }
            guard tokens.allSatisfy({ haystack.contains($0) }) else { continue }
            let score = tokens.reduce(0) { $0 + (entry.title.hasPrefix($1) ? 4 : entry.title.contains($1) ? 2 : 0) }
            matches.append((entry.destination, score))
        }
        matches.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.id < $1.0.id
        }
        return Task.isCancelled ? [] : matches.prefix(limit).map(\.0)
    }

    /// Reuses the normalized catalog for each query until the underlying metadata changes.
    func search(_ query: String, limit: Int = 100) -> [GlobalSearchEntry] {
        let tokens = Self.normalize(String(query.prefix(200))).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty, limit > 0 else { return [] }
        var matches: [(GlobalSearchEntry, Int)] = []
        for entry in indexedEntries {
            guard !Task.isCancelled else { return [] }
            guard tokens.allSatisfy({ entry.searchable.contains($0) }) else { continue }
            let score = tokens.reduce(0) { $0 + (entry.title.hasPrefix($1) ? 4 : entry.title.contains($1) ? 2 : 0) }
            matches.append((entry.destination, score))
        }
        matches.sort {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.id < $1.0.id
        }
        return Task.isCancelled ? [] : matches.prefix(limit).map(\.0)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }
}
