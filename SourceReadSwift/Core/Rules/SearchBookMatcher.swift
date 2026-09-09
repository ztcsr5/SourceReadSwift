import Foundation

enum SearchBookMatcher {
    static func normalized(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
            .lowercased()
    }

    static func cleanTitle(_ value: String) -> String {
        var s = normalized(value)
        s = s.replacingOccurrences(of: #"(?:\[|【|\(|（)[^】\)\]]*?(?:完结|连载|精校|全本|全集|校对|txt|更新|免费|完|合集|修复|修仙|玄幻|都市|科幻|网游|历史|言情|同人)[^】\)\]]*?(?:\]|】|\)|）)"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^\[[^\]]+\]"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"^【[^】]+】"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?:txt下载|txt|最新章节|全文阅读|全集|全本|精校版|校对版|无弹窗)$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[《》「」『』【】\[\]\(\)（）]"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanAuthor(_ value: String) -> String {
        var s = normalized(value)
        s = s.replacingOccurrences(of: #"^(?:作者|作\s*者)[:：\s]*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s*著$"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[《》「」『』【】\[\]\(\)（）]"#, with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isExactMatch(book: SearchBook, query: String) -> Bool {
        let normName = normalized(book.name)
        let cleanedName = cleanTitle(book.name)
        let normAuthor = normalized(book.author ?? "")
        let cleanedAuthor = cleanAuthor(book.author ?? "")

        if normName == query || cleanedName == query {
            return true
        }
        if !normAuthor.isEmpty && (normAuthor == query || cleanedAuthor == query) {
            return true
        }
        if normName.hasPrefix(query) {
            let suffix = normName.dropFirst(query.count)
            if suffix.isEmpty { return true }
            if let firstChar = suffix.first, " (（[【:：-_/·.t".contains(firstChar) {
                return true
            }
        }
        return false
    }

    static func filteredAndRanked(
        _ books: [SearchBook],
        keyword: String,
        exact: Bool
    ) -> [SearchBook] {
        let query = normalized(keyword)
        guard !query.isEmpty else { return [] }

        let unique = deduplicated(books)

        let matched = unique.filter { book in
            let name = normalized(book.name)
            let author = normalized(book.author ?? "")
            if exact {
                return isExactMatch(book: book, query: query)
            }
            return name.contains(query) || author.contains(query)
        }

        return matched.sorted { lhs, rhs in
            let left = score(lhs, query: query)
            let right = score(rhs, query: query)
            if left != right { return left > right }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.sourceName.localizedStandardCompare(rhs.sourceName) == .orderedAscending
        }
    }

    /// De-duplicates incrementally collected source results while retaining
    /// the first source's metadata.  Search requests arrive out of order, so
    /// the caller can run this after each batch without reshuffling equal
    /// scores unpredictably.
    static func deduplicated(_ books: [SearchBook]) -> [SearchBook] {
        var seenIDs = Set<String>()
        return books.filter { book in
            let name = normalized(book.name)
            guard !name.isEmpty else { return false }
            let normalizedURL = canonicalURL(book.bookUrl)
            let source = canonicalURL(book.sourceUrl)
            let id = "\(source)|\(normalizedURL)"
            // Some sources return the same item once as an absolute URL and
            // once as a path. Keep distinct source URLs, but collapse exact
            // duplicates from the same source regardless of slash casing.
            return seenIDs.insert(id).inserted
        }
    }

    static func canonicalURL(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let components = URLComponents(string: trimmed), components.scheme != nil else {
            return trimmed
        }
        var normalized = components
        normalized.scheme = components.scheme?.lowercased()
        normalized.host = components.host?.lowercased()
        return normalized.string ?? trimmed
    }

    private static func score(_ book: SearchBook, query: String) -> Int {
        let name = normalized(book.name)
        let cleanedName = cleanTitle(book.name)
        let author = normalized(book.author ?? "")
        let cleanedAuthor = cleanAuthor(book.author ?? "")
        if name == query { return 500 }
        if cleanedName == query { return 450 }
        if name.hasPrefix(query) { return 350 }
        if cleanedName.hasPrefix(query) { return 300 }
        if name.contains(query) { return 250 }
        if author == query || cleanedAuthor == query { return 200 }
        if author.contains(query) { return 100 }
        return 0
    }
}
