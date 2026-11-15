import Foundation

/// Keeps scripted listings from being cancelled before the transport's default timeout.
enum SourceListingBudget {
    private static let plainSearch: TimeInterval = 10
    private static let plainExplore: TimeInterval = 12

    static func search(for source: BookSource) -> TimeInterval {
        hasJavaScript(source.searchUrl) || hasJavaScript(source.ruleSearch?.fields["bookList"])
            ? SourceRequestBuilder.defaultTimeout : plainSearch
    }

    static func explore(for source: BookSource, url: String) -> TimeInterval {
        hasJavaScript(source.exploreUrl) || hasJavaScript(url) || hasJavaScript(source.ruleExplore?.fields["bookList"])
            ? SourceRequestBuilder.defaultTimeout : plainExplore
    }

    private static func hasJavaScript(_ rule: String?) -> Bool {
        guard let rule else { return false }
        return rule.range(of: "@js:", options: .caseInsensitive) != nil
            || rule.range(of: "<js>", options: .caseInsensitive) != nil
    }
}

extension SourceEngine {
    /// Searches one source with a bounded deadline without stalling the search window.
    func searchBooksWithinListingBudget(source: BookSource, keyword: String, page: Int) async
        -> Result<[SearchBook], SourceEngineError> {
        let seconds = SourceListingBudget.search(for: source)
        return await AsyncTimeout.run(seconds: seconds) {
            await self.searchBooks(source: source, keyword: keyword, page: page)
        } ?? .failure(.network("搜索超时（超过 \(Int(seconds)) 秒）"))
    }
}
