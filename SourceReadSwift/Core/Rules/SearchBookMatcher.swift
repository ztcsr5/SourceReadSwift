import Foundation

enum SearchBookMatcher {
    // MARK: - Regex cache
    //
    // `String.replacingOccurrences(of:with:options:.regularExpression)` compiles a
    // fresh ICU pattern on every call. Ranking normalises every field of every row,
    // and the sort comparator used to redo that work on each comparison, so pattern
    // compilation dominated search UI time. Compiling each literal once removes it.

    private final class RegexCache: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String: NSRegularExpression] = [:]

        func regex(_ pattern: String) -> NSRegularExpression? {
            lock.lock()
            if let cached = storage[pattern] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
            lock.lock()
            storage[pattern] = compiled
            lock.unlock()
            return compiled
        }
    }

    private static let regexCache = RegexCache()

    private static func removing(_ pattern: String, from value: String) -> String {
        guard let regex = regexCache.regex(pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return regex.stringByReplacingMatches(in: value, options: [], range: range, withTemplate: "")
    }

    /// e.g. `【完结】斗破苍穹txt下载`
    private static let decoratedTitlePattern = #"(?:\[|【|\(|（)[^】\)\]]*?(?:完结|连载|精校|全本|全集|校对|txt|更新|免费|完|合集|修复|修仙|玄幻|都市|科幻|网游|历史|言情|同人)[^】\)\]]*?(?:\]|】|\)|）)"#
    private static let leadingSquareBracketPattern = #"^\[[^\]]+\]"#
    private static let leadingCJKBracketPattern = #"^【[^】]+】"#
    private static let trailingNoisePattern = #"(?:txt下载|txt|最新章节|全文阅读|全集|全本|精校版|校对版|无弹窗)$"#
    private static let decorativeCharactersPattern = #"[《》「」『』【】\[\]\(\)（）]"#
    private static let authorPrefixPattern = #"^(?:作者|作\s*者)[:：\s]*"#
    private static let authorSuffixPattern = #"\s*著$"#

    // MARK: - Normalisation

    static func normalized(_ value: String) -> String {
        let precomposed = value
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "《", with: "")
            .replacingOccurrences(of: "》", with: "")
        // Same result as removing `\s+` with ICU, without compiling a pattern.
        let withoutWhitespace = precomposed.filter { !$0.isWhitespace }
        return withoutWhitespace.lowercased()
    }

    static func cleanTitle(_ value: String) -> String {
        cleanTitle(fromNormalized: normalized(value))
    }

    private static func cleanTitle(fromNormalized base: String) -> String {
        var s = base
        s = removing(decoratedTitlePattern, from: s)
        s = removing(leadingSquareBracketPattern, from: s)
        s = removing(leadingCJKBracketPattern, from: s)
        s = removing(trailingNoisePattern, from: s)
        s = removing(decorativeCharactersPattern, from: s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanAuthor(_ value: String) -> String {
        cleanAuthor(fromNormalized: normalized(value))
    }

    private static func cleanAuthor(fromNormalized base: String) -> String {
        var s = base
        s = removing(authorPrefixPattern, from: s)
        s = removing(authorSuffixPattern, from: s)
        s = removing(decorativeCharactersPattern, from: s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Ranking

    /// Every normalised form of one row, computed exactly once per ranking pass.
    /// The previous implementation recomputed all four forms inside the sort
    /// comparator, i.e. O(n log n) times instead of O(n).
    private struct BookProfile {
        let name: String
        let cleanedName: String
        let author: String
        let cleanedAuthor: String
    }

    private static func profile(for book: SearchBook) -> BookProfile {
        let normName = normalized(book.name)
        let normAuthor = normalized(book.author ?? "")
        return BookProfile(
            name: normName,
            cleanedName: cleanTitle(fromNormalized: normName),
            author: normAuthor,
            cleanedAuthor: cleanAuthor(fromNormalized: normAuthor)
        )
    }

    static func isExactMatch(book: SearchBook, query: String) -> Bool {
        isExactMatch(profile(for: book), query: query)
    }

    private static func isExactMatch(_ profile: BookProfile, query: String) -> Bool {
        if profile.name == query || profile.cleanedName == query {
            return true
        }
        if !profile.author.isEmpty && (profile.author == query || profile.cleanedAuthor == query) {
            return true
        }
        if profile.name.hasPrefix(query) {
            let suffix = profile.name.dropFirst(query.count)
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
        var ranked: [(book: SearchBook, score: Int, order: Int)] = []
        ranked.reserveCapacity(unique.count)

        for (order, book) in unique.enumerated() {
            let bookProfile = profile(for: book)
            let matched: Bool
            if exact {
                matched = isExactMatch(bookProfile, query: query)
            } else {
                matched = bookProfile.name.contains(query) || bookProfile.author.contains(query)
            }
            guard matched else { continue }
            ranked.append((book: book, score: score(bookProfile, query: query), order: order))
        }

        ranked.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.book.name != rhs.book.name {
                return lhs.book.name.localizedStandardCompare(rhs.book.name) == .orderedAscending
            }
            if lhs.book.sourceName != rhs.book.sourceName {
                return lhs.book.sourceName.localizedStandardCompare(rhs.book.sourceName) == .orderedAscending
            }
            // Previously unspecified for fully equal rows; pinning to input order
            // keeps streamed batches from reshuffling as more rows arrive.
            return lhs.order < rhs.order
        }
        return ranked.map { $0.book }
    }

    /// De-duplicates incrementally collected source results while retaining
    /// the first source's metadata.  Search requests arrive out of order, so
    /// the caller can run this after each batch without reshuffling equal
    /// scores unpredictably.
    static func deduplicated(_ books: [SearchBook]) -> [SearchBook] {
        var seenIDs = Set<String>()
        var result: [SearchBook] = []
        result.reserveCapacity(books.count)
        for book in books {
            let name = normalized(book.name)
            guard !name.isEmpty else { continue }
            let normalizedURL = canonicalURL(book.bookUrl)
            let source = canonicalURL(book.sourceUrl)
            let id = "\(source)|\(normalizedURL)"
            // Some sources return the same item once as an absolute URL and
            // once as a path. Keep distinct source URLs, but collapse exact
            // duplicates from the same source regardless of slash casing.
            if seenIDs.insert(id).inserted {
                result.append(book)
            }
        }
        return result
    }

    /// Stable identity used by both de-duplication and incremental merging.
    /// Mirrors `deduplicated`; returns nil when the row has no usable title.
    static func identityKey(for book: SearchBook) -> String? {
        let name = normalized(book.name)
        guard !name.isEmpty else { return nil }
        return "\(canonicalURL(book.sourceUrl))|\(canonicalURL(book.bookUrl))"
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

    private static func score(_ profile: BookProfile, query: String) -> Int {
        if profile.name == query { return 500 }
        if profile.cleanedName == query { return 450 }
        if profile.name.hasPrefix(query) { return 350 }
        if profile.cleanedName.hasPrefix(query) { return 300 }
        if profile.name.contains(query) { return 250 }
        if profile.author == query || profile.cleanedAuthor == query { return 200 }
        if profile.author.contains(query) { return 100 }
        return 0
    }
}
