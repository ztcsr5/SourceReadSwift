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
}

enum GlobalSearchIndex {
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
            entries.append(.init(id: "book:" + book.id, kind: .book, title: book.title,
                subtitle: [book.author, book.groupName, book.intro].compactMap { $0 }.joined(separator: " · "),
                target: book.id))
            for bookmark in book.bookmarks ?? [] {
                entries.append(.init(id: "bookmark:" + book.id + ":" + bookmark.id, kind: .bookmark,
                    title: bookmark.chapterTitle, subtitle: book.title + " · " + bookmark.snippet,
                    target: book.id, bookmarkID: bookmark.id))
            }
        }
        entries += sources.map { source in
            .init(id: "source:" + source.id, kind: .source, title: source.bookSourceName,
                  subtitle: source.bookSourceGroup ?? "书源", target: source.bookSourceName)
        }
        return entries
    }

    /// Matches every query token, ranks titles first and bounds the rendered result count.
    static func search(_ query: String, entries: [GlobalSearchEntry], limit: Int = 100) -> [GlobalSearchEntry] {
        let tokens = normalize(String(query.prefix(200))).split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty, limit > 0 else { return [] }
        return entries.compactMap { entry -> (GlobalSearchEntry, Int)? in
            let title = normalize(entry.title)
            let searchable = title + " " + normalize(entry.subtitle)
            guard tokens.allSatisfy({ searchable.contains($0) }) else { return nil }
            let score = tokens.reduce(0) { $0 + (title.hasPrefix($1) ? 4 : title.contains($1) ? 2 : 0) }
            return (entry, score)
        }.sorted {
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.id < $1.0.id
        }.prefix(limit).map(\.0)
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }
}
