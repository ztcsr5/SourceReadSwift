import Foundation
import SwiftSoup

struct SearchResultParser {
    private let htmlExtractor: HtmlRuleExtractor
    private let jsonExtractor: JSONRuleExtractor

    init(executionContext: RuleExecutionContext = RuleExecutionContext()) {
        self.htmlExtractor = HtmlRuleExtractor(executionContext: executionContext)
        self.jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
    }

    func parse(source: BookSource, response: SourceResponse) -> Result<[SearchBook], SourceEngineError> {
        let normalized = ResponseFormatDetector.normalizedBody(response.body)
        let normalizedResponse = SourceResponse(
            url: response.url,
            statusCode: response.statusCode,
            headers: response.headers,
            body: normalized,
            data: response.data,
            encodedByteCount: response.encodedByteCount,
            bodyWasDecoded: response.bodyWasDecoded,
            contentEncodings: response.contentEncodings
        )
        let listRule = firstRule(source.ruleSearch, keys: ["bookList", "list", "books"])
        let isJSRule = listRule.map { LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:") } ?? false
        if isJSRule || ResponseFormatDetector.prefersJSON(body: normalized, headers: response.headers, rule: listRule) {
            let jsonResult = parseJSON(source: source, response: normalizedResponse)
            switch jsonResult {
            case .success:
                return jsonResult
            case .failure:
                let htmlResult = parseHTML(source: source, response: normalizedResponse)
                if case .success = htmlResult {
                    return htmlResult
                }
                return jsonResult
            }
        } else {
            let htmlResult = parseHTML(source: source, response: normalizedResponse)
            switch htmlResult {
            case .success:
                return htmlResult
            case .failure:
                let jsonResult = parseJSON(source: source, response: normalizedResponse)
                if case .success = jsonResult {
                    return jsonResult
                }
                return htmlResult
            }
        }
    }

    private func parseHTML(source: BookSource, response: SourceResponse) -> Result<[SearchBook], SourceEngineError> {
        guard let rule = source.ruleSearch else {
            return .failure(.rule("ruleSearch 为空"))
        }
        guard let listRule = firstRule(rule, keys: ["bookList", "list", "books"]) else {
            return .failure(.rule("ruleSearch.bookList 为空"))
        }

        do {
            let roots: [Element]
            if let initRule = firstRule(rule, keys: ["init"]) {
                roots = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: initRule)
            } else {
                roots = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html")
            }
            var elements = try roots.flatMap { root in
                try htmlExtractor.select(from: root, rule: listRule, baseUrl: response.url)
            }
            if elements.isEmpty {
                let fallbackSelectors = [
                    "table.cytable tr:gt(0)",
                    ".cytable tr:gt(0)",
                    "table.cytable tr",
                    ".cytable tr",
                    "table.grid tr:gt(0)",
                    "table.grid tr",
                    "table.list tr:gt(0)",
                    "table.list tr",
                    "table tr:has(a)",
                    ".book-item",
                    ".search-item",
                    ".search-list-item",
                    ".so-item",
                    ".s-item",
                    ".list-item",
                    "ul.list li",
                    ".bookbox",
                    ".booklist li",
                    ".se-result",
                    ".se-result-item",
                    ".result-item",
                    ".search-result",
                    ".search-result-item",
                    ".item",
                    "div.bookbox"
                ]
                for selector in fallbackSelectors {
                    let candidates = try roots.flatMap { root in
                        try htmlExtractor.select(from: root, rule: selector, baseUrl: response.url)
                    }
                    if !candidates.isEmpty {
                        elements = candidates
                        break
                    }
                }
            }

            var books: [SearchBook] = []
            let variables: [String: Any] = [
                "source": source,
                "baseUrl": response.url.absoluteString,
                "result": response.body,
                "body": response.body,
                "src": response.body,
                "html": response.body
            ]
            for element in elements {
                var rawName = (try? htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["name", "bookName"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                if rawName == nil {
                    rawName = (try? htmlExtractor.value(from: element, rule: "a.track@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "td:eq(1) a@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "a@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? element.select("a").first()?.text())?.nilIfEmpty
                }
                let name = rawName?.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawName

                var rawBookUrl = (try? htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["bookUrl", "url"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                if rawBookUrl == nil {
                    rawBookUrl = (try? htmlExtractor.value(from: element, rule: "a.track@href", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "td:eq(1) a@href", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "a@href", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? element.select("a").first()?.attr("href"))?.nilIfEmpty
                }
                let bookUrl = rawBookUrl?.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawBookUrl

                guard let name, !name.isEmpty, let bookUrl, !bookUrl.isEmpty, !bookUrl.lowercased().hasPrefix("javascript:"), bookUrl != "#" else { continue }
                let absBookUrl = htmlExtractor.absolutize(bookUrl, base: response.url)
                guard !absBookUrl.isEmpty else { continue }

                var author = (try? htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["author"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                if author == nil {
                    author = (try? htmlExtractor.value(from: element, rule: "td:eq(0) a@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "td:eq(0)@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "a[href*=author]@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                }
                author = author?.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? author

                let rawCover = try? htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["coverUrl", "cover"]), fallback: "img@src", baseUrl: response.url, variables: variables).nilIfEmpty
                let cover = rawCover?.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawCover
                let kind = try? htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["kind"]), fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                let lastChapter = try? htmlExtractor.value(from: element, rule: firstRule(rule, keys: ["lastChapter"]), fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                books.append(SearchBook(
                    name: name,
                    author: author,
                    coverUrl: cover,
                    bookUrl: absBookUrl,
                    sourceName: source.bookSourceName,
                    sourceUrl: source.bookSourceUrl,
                    intro: nil,
                    kind: kind,
                    lastChapter: lastChapter
                ))
            }
            if elements.isEmpty {
                let document = try SwiftSoup.parse(response.body, response.url.absoluteString)
                let detailRule = source.ruleBookInfo
                let name = (try? htmlExtractor.value(from: document, rule: firstRule(detailRule, keys: ["name", "bookName"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                    ?? (try? document.select("meta[property=og:novel:book_name]").attr("content"))?.nilIfEmpty
                    ?? (try? document.select("meta[property=og:title]").attr("content"))?.nilIfEmpty
                if let name, !name.isEmpty {
                    let author = (try? htmlExtractor.value(from: document, rule: firstRule(detailRule, keys: ["author"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? document.select("meta[property=og:novel:author]").attr("content"))?.nilIfEmpty
                    let cover = (try? htmlExtractor.value(from: document, rule: firstRule(detailRule, keys: ["coverUrl", "cover"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? document.select("meta[property=og:image]").attr("content"))?.nilIfEmpty
                    let intro = (try? htmlExtractor.value(from: document, rule: firstRule(detailRule, keys: ["intro", "introduction"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? document.select("meta[property=og:description]").attr("content"))?.nilIfEmpty
                    return .success([SearchBook(
                        name: name,
                        author: author,
                        coverUrl: cover,
                        bookUrl: response.url.absoluteString,
                        sourceName: source.bookSourceName,
                        sourceUrl: source.bookSourceUrl,
                        intro: intro
                    )])
                }
            }
            return books.isEmpty ? .failure(.empty("搜索解析结果为空")) : .success(books)
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, response: SourceResponse) -> Result<[SearchBook], SourceEngineError> {
        let variables: [String: Any] = [
            "source": source,
            "baseUrl": response.url.absoluteString,
            "result": response.body,
            "body": response.body,
            "src": response.body,
            "html": response.body
        ]
        let extractor = jsonExtractor
        let rule = source.ruleSearch
        let listRule = firstRule(rule, keys: ["bookList", "list", "books"])
        let isJSRule = listRule.map { LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:") } ?? false

        let rootObject: Any
        if let object = ResponseFormatDetector.jsonObject(from: response.body) {
            if let initRule = firstRule(rule, keys: ["init"]),
               let initialized = extractor.value(from: object, path: initRule, variables: variables) {
                rootObject = initialized
            } else {
                rootObject = object
            }
        } else if isJSRule {
            rootObject = response.body
        } else {
            return .failure(.rule("JSON 解析失败"))
        }
        let candidates = extractor.list(from: rootObject, rule: listRule, variables: variables).prefix(120)
        let books = candidates.compactMap { item -> SearchBook? in
            let name = extractor.string(
                from: item,
                rule: firstRule(rule, keys: ["name", "bookName"]),
                fallbackKeys: ["name", "bookName", "title", "book_name"],
                variables: variables
            )
            let url = extractor.string(
                from: item,
                rule: firstRule(rule, keys: ["bookUrl", "url"]),
                fallbackKeys: ["bookUrl", "url", "link", "book_url", "id"],
                variables: variables
            )
            guard let name, let url, !url.isEmpty, !url.lowercased().hasPrefix("javascript:"), url != "#" else { return nil }
            let absBookUrl: String
            let isBareID = !url.contains("/") && !url.contains(".") && !url.contains("?") && !url.contains("=")
            if isBareID {
                if (response.url.host?.contains("mowan") == true || source.bookSourceUrl.contains("mowan")),
                   let itemId = item["id"] as? String ?? item["book_id"] as? String ?? (url as String?),
                   let itemSource = item["source"] as? String {
                    absBookUrl = "https://www.mowan.lol/api/book/detail?source=\(itemSource)&book_id=\(itemId)"
                } else if response.url.path.contains("/api/") || response.url.path.contains("/search") {
                    if let baseURL = URL(string: source.cleanSourceURL), baseURL.scheme != nil {
                        absBookUrl = htmlExtractor.absolutize(url, base: baseURL)
                    } else {
                        absBookUrl = htmlExtractor.absolutize(url, base: response.url)
                    }
                } else {
                    absBookUrl = htmlExtractor.absolutize(url, base: response.url)
                }
            } else {
                absBookUrl = htmlExtractor.absolutize(url, base: response.url)
            }
            guard !absBookUrl.isEmpty else { return nil }
            return SearchBook(
                name: name,
                author: extractor.string(
                    from: item,
                    rule: firstRule(rule, keys: ["author"]),
                    fallbackKeys: ["author", "writer"],
                    variables: variables
                ),
                coverUrl: extractor.string(
                    from: item,
                    rule: firstRule(rule, keys: ["coverUrl", "cover"]),
                    fallbackKeys: ["cover", "coverUrl", "img", "image"],
                    variables: variables
                ),
                bookUrl: absBookUrl,
                sourceName: source.bookSourceName,
                sourceUrl: source.bookSourceUrl,
                intro: extractor.string(
                    from: item,
                    rule: firstRule(rule, keys: ["intro"]),
                    fallbackKeys: ["intro", "desc", "description"],
                    variables: variables
                ),
                kind: extractor.string(
                    from: item,
                    rule: firstRule(rule, keys: ["kind"]),
                    fallbackKeys: ["kind", "category", "tag", "tags"],
                    variables: variables
                ),
                lastChapter: extractor.string(
                    from: item,
                    rule: firstRule(rule, keys: ["lastChapter"]),
                    fallbackKeys: ["lastChapter", "latestChapter", "last_chapter_title"],
                    variables: variables
                )
            )
        }
        return books.isEmpty ? .failure(.empty("JSON 搜索解析结果为空")) : .success(Array(books))
    }

    private func firstRule(_ rule: SourceRule?, keys: [String]) -> String? {
        guard let rule else { return nil }
        for key in keys {
            if let value = rule.fields[key], !value.isEmpty {
                return value
            }
        }
        return rule.raw
    }

}
