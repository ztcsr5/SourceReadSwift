import Foundation

/// Loads RSS/Atom or a subscription's declarative list rules without changing the saved feed identity.
struct RSSFeedLoader: Sendable {
    private let client: any SourceNetworkClient
    private let maximumBytes = 4 * 1024 * 1024
    private static let maximumArticles = 100

    init(client: any SourceNetworkClient = URLSessionSourceNetworkClient()) {
        self.client = client
    }

    func load(_ source: RSSSource) async throws -> [RSSArticlePreview] {
        let entered = source.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: entered), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else {
            throw Issue.invalidURL
        }
        var headers = SourceImportDownloader.requestHeaders
        headers["Accept"] = "application/rss+xml,application/atom+xml,application/xml,text/xml,application/json,text/html,*/*"
        let request = SourceRequest(url: url, method: .get, headers: headers, body: nil, expectedCharset: nil, timeout: 18)
        let response = try await client.load(request).get()
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else { throw Issue.http(response.statusCode) }
        guard response.data.count <= maximumBytes, response.body.utf8.count <= maximumBytes else { throw Issue.tooLarge }
        guard !SourceImportDownloader.looksLikeChallenge(text: response.body, headers: response.headers) else {
            throw Issue.notAFeed
        }
        return try await Task.detached(priority: .utility) {
            try Self.parse(response, source: source)
        }.value
    }

    private static func parse(_ response: SourceResponse, source: RSSSource) throws -> [RSSArticlePreview] {
        let parser = RSSFeedParser()
        if parser.feedName(in: response.body) != nil {
            return Array(parser.parseArticles(from: response.body, sourceURL: source.sourceUrl,
                                              responseURL: response.url.absoluteString).prefix(maximumArticles))
        }
        guard let rule = source.ruleArticles?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { throw Issue.notAFeed }
        let configured = [rule, source.ruleTitle, source.ruleLink, source.ruleDescription, source.rulePubDate, source.ruleImage]
            .compactMap { $0 }
        // This feed reader uses declarative rules only; a network-dependent JS
        // source needs a regular RSS endpoint rather than silently running nothing.
        guard !configured.contains(where: { $0.range(of: "@js:|<js>|\\{\\{", options: [.caseInsensitive, .regularExpression]) != nil }) else {
            throw Issue.scriptRule
        }
        let articles: [RSSArticlePreview]
        if let json = ResponseFormatDetector.jsonObject(from: response.body) {
            let extractor = JSONRuleExtractor()
            articles = try extract(extractor.list(from: json, rule: rule).prefix(maximumArticles), for: source, base: response.url) { row, rule, key in
                extractor.string(from: row, rule: rule, fallbackKeys: [key])
            }
        } else {
            let extractor = HtmlRuleExtractor()
            let rows = try extractor.select(response.body, baseUrl: response.url, listRule: rule)
            let fallback = ["title": "text", "link": "a@href", "description": "p@text", "image": "img@src"]
            articles = try extract(rows.prefix(maximumArticles), for: source, base: response.url) { row, rule, key in
                try extractor.value(from: row, rule: rule, fallback: fallback[key], baseUrl: response.url)
            }
        }
        guard !articles.isEmpty else { throw Issue.noRuleMatches }
        var seen = Set<String>()
        return articles.filter { seen.insert($0.id).inserted }
    }

    private static func extract<Rows: Sequence>(
        _ rows: Rows, for source: RSSSource, base: URL,
        read: (Rows.Element, String?, String) throws -> String?
    ) throws -> [RSSArticlePreview] {
        try rows.compactMap { row in
            guard let title = try read(row, source.ruleTitle, "title")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
            let link = try read(row, source.ruleLink, "link").flatMap { MediaURLResolver.resolve($0, base: base.absoluteString) }
            let image = try read(row, source.ruleImage, "image").flatMap { MediaURLResolver.resolve($0, base: base.absoluteString) }
            return RSSArticlePreview(title: title, link: link, pubDate: try read(row, source.rulePubDate, "pubDate"),
                description: try read(row, source.ruleDescription, "description"), sourceURL: source.sourceUrl, imageURL: image)
        }
    }

    enum Issue: LocalizedError, Equatable {
        case invalidURL, tooLarge, notAFeed, noRuleMatches, scriptRule
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "订阅地址无效。请填入 HTTP 或 HTTPS 的 RSS/Atom 地址。"
            case .tooLarge: return "订阅超过 4 MB，未替换已保存的文章。"
            case .notAFeed: return "该地址没有返回 RSS/Atom。请检查是否复制了网页地址或遇到访问验证。"
            case .noRuleMatches: return "没有匹配到文章。请检查文章列表和标题规则。"
            case .scriptRule: return "这个订阅使用脚本型文章规则。请改用该站提供的 RSS/Atom 直链。"
            case .http(let code): return "订阅服务器返回 HTTP \(code)。请检查地址或稍后重试。"
            }
        }
    }
}
