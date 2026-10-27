import Foundation
import SwiftSoup

struct SearchResultParser {
    private let htmlExtractor: HtmlRuleExtractor
    private let jsonExtractor: JSONRuleExtractor

    init(executionContext: RuleExecutionContext = RuleExecutionContext()) {
        self.htmlExtractor = HtmlRuleExtractor(executionContext: executionContext)
        self.jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
    }

    func parse(source: BookSource, response: SourceResponse, ruleOverride: SourceRule? = nil, keyword: String? = nil) -> Result<[SearchBook], SourceEngineError> {
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
        let effectiveRule = ruleOverride ?? source.ruleSearch
        let listRule = firstRule(effectiveRule, fallback: source.ruleSearch, keys: ["bookList", "list", "books"])
        let isJSRule = listRule.map { LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:") } ?? false
        // 空结果不触发兜底是旧行为：诊断里 168 条「搜索解析结果为空」都是
        // success(0 条) 直接返回，永远试不到另一套提取器。这里把「空」当成一次机会。
        if isJSRule || ResponseFormatDetector.prefersJSON(body: normalized, headers: response.headers, rule: listRule) {
            let jsonResult = parseJSON(source: source, response: normalizedResponse, ruleOverride: ruleOverride, keyword: keyword)
            switch jsonResult {
            case .success(let books) where !books.isEmpty:
                return jsonResult
            case .success:
                let htmlResult = parseHTML(source: source, response: normalizedResponse, ruleOverride: ruleOverride, keyword: keyword)
                if case .success(let htmlBooks) = htmlResult, !htmlBooks.isEmpty {
                    return htmlResult
                }
                return jsonResult
            case .failure:
                let htmlResult = parseHTML(source: source, response: normalizedResponse, ruleOverride: ruleOverride, keyword: keyword)
                if case .success = htmlResult {
                    return htmlResult
                }
                return jsonResult
            }
        } else {
            let htmlResult = parseHTML(source: source, response: normalizedResponse, ruleOverride: ruleOverride, keyword: keyword)
            switch htmlResult {
            case .success(let books) where !books.isEmpty:
                return htmlResult
            case .success:
                let jsonResult = parseJSON(source: source, response: normalizedResponse, ruleOverride: ruleOverride, keyword: keyword)
                if case .success(let jsonBooks) = jsonResult, !jsonBooks.isEmpty {
                    return jsonResult
                }
                return htmlResult
            case .failure:
                let jsonResult = parseJSON(source: source, response: normalizedResponse, ruleOverride: ruleOverride, keyword: keyword)
                if case .success = jsonResult {
                    return jsonResult
                }
                return htmlResult
            }
        }
    }

    private func parseHTML(source: BookSource, response: SourceResponse, ruleOverride: SourceRule? = nil, keyword: String? = nil) -> Result<[SearchBook], SourceEngineError> {
        let rule = ruleOverride ?? source.ruleSearch
        guard let rule else {
            return .failure(.rule("搜索与发现规则均为空"))
        }
        guard let listRule = firstRule(rule, fallback: source.ruleSearch, keys: ["bookList", "list", "books"]) else {
            return .failure(.rule("bookList 规则为空"))
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
                var rawName = (try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["name", "bookName"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                if rawName == nil {
                    rawName = (try? htmlExtractor.value(from: element, rule: "a.track@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "td:eq(1) a@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "a@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? element.select("a").first()?.text())?.nilIfEmpty
                }
                let name = rawName?.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawName

                var rawBookUrl = (try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["bookUrl", "url"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
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

                var author = (try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["author"]), fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                if author == nil {
                    author = (try? htmlExtractor.value(from: element, rule: "td:eq(0) a@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "td:eq(0)@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                        ?? (try? htmlExtractor.value(from: element, rule: "a[href*=author]@text", fallback: nil, baseUrl: response.url, variables: variables))?.nilIfEmpty
                }
                author = author?.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? author

                let rawCover = try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["coverUrl", "cover"]), fallback: "img@src", baseUrl: response.url, variables: variables).nilIfEmpty
                let cover = rawCover?.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.trimmingCharacters(in: .whitespacesAndNewlines) ?? rawCover
                let intro = try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["intro"]), fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                let kind = try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["kind"]), fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                let lastChapter = try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["lastChapter"]), fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                let wordCount = try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["wordCount", "wordNum", "words"]), fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                let checkKeyWord = try? htmlExtractor.value(from: element, rule: firstRule(rule, fallback: source.ruleSearch, keys: ["checkKeyWord"]), fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                guard passesCheckKeyWord(checkKeyWord, keyword: keyword) else { continue }
                books.append(SearchBook(
                    name: name,
                    author: author,
                    coverUrl: cover,
                    bookUrl: absBookUrl,
                    sourceName: source.bookSourceName,
                    sourceUrl: source.bookSourceUrl,
                    intro: intro,
                    kind: kind,
                    lastChapter: lastChapter,
                    wordCount: wordCount,
                    checkKeyWord: checkKeyWord
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
            if books.isEmpty {
                let message = elements.isEmpty
                    ? "搜索列表规则未命中（0 个节点，响应 \(response.body.count) 字符）"
                    : "搜索列表命中 \(elements.count) 个节点但书名或链接为空"
                return .failure(.empty(message))
            }
            return .success(books)
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, response: SourceResponse, ruleOverride: SourceRule? = nil, keyword: String? = nil) -> Result<[SearchBook], SourceEngineError> {
        let variables: [String: Any] = [
            "source": source,
            "baseUrl": response.url.absoluteString,
            "result": response.body,
            "body": response.body,
            "src": response.body,
            "html": response.body
        ]
        let extractor = jsonExtractor
        let rule = ruleOverride ?? source.ruleSearch
        let listRule = firstRule(rule, fallback: source.ruleSearch, keys: ["bookList", "list", "books"])
        let isJSRule = listRule.map { LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:") } ?? false

        let initRule = firstRule(rule, fallback: source.ruleSearch, keys: ["init"])
        let initIsJS = initRule.map {
            LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:")
        } ?? false
        let rootObject: Any
        if let object = ResponseFormatDetector.jsonObject(from: response.body) {
            if let initRule,
               let initialized = extractor.value(from: object, path: initRule, variables: variables) {
                rootObject = ResponseFormatDetector.jsonContainer(from: initialized)
            } else {
                rootObject = object
            }
        } else if let initRule, initIsJS,
                  let initialized = extractor.value(from: response.body, path: initRule, variables: variables) {
            // Legado evaluates `init` before the field rules.  A JavaScript
            // init may turn a non-JSON payload (encrypted text, concatenated
            // fragments, HTML wrappers) into a JSON container.
            rootObject = ResponseFormatDetector.jsonContainer(from: initialized)
        } else if isJSRule {
            rootObject = response.body
        } else {
            return .failure(.rule("JSON 解析失败"))
        }
        let candidates = extractor.list(from: rootObject, rule: listRule, variables: variables).prefix(120)
        let books = candidates.compactMap { item -> SearchBook? in
            let name = extractor.string(
                from: item,
                rule: firstRule(rule, fallback: source.ruleSearch, keys: ["name", "bookName"]),
                fallbackKeys: ["name", "bookName", "title", "book_name"],
                variables: variables
            )
            let url = extractor.string(
                from: item,
                rule: firstRule(rule, fallback: source.ruleSearch, keys: ["bookUrl", "url"]),
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
                    rule: firstRule(rule, fallback: source.ruleSearch, keys: ["author"]),
                    fallbackKeys: ["author", "writer"],
                    variables: variables
                ),
                coverUrl: extractor.string(
                    from: item,
                    rule: firstRule(rule, fallback: source.ruleSearch, keys: ["coverUrl", "cover"]),
                    fallbackKeys: ["cover", "coverUrl", "img", "image"],
                    variables: variables
                ),
                bookUrl: absBookUrl,
                sourceName: source.bookSourceName,
                sourceUrl: source.bookSourceUrl,
                intro: extractor.string(
                    from: item,
                    rule: firstRule(rule, fallback: source.ruleSearch, keys: ["intro"]),
                    fallbackKeys: ["intro", "desc", "description"],
                    variables: variables
                ),
                kind: extractor.string(
                    from: item,
                    rule: firstRule(rule, fallback: source.ruleSearch, keys: ["kind"]),
                    fallbackKeys: ["kind", "category", "tag", "tags"],
                    variables: variables
                ),
                lastChapter: extractor.string(
                    from: item,
                    rule: firstRule(rule, fallback: source.ruleSearch, keys: ["lastChapter"]),
                    fallbackKeys: ["lastChapter", "latestChapter", "last_chapter_title"],
                    variables: variables
                ),
                wordCount: extractor.string(
                    from: item,
                    rule: firstRule(rule, fallback: source.ruleSearch, keys: ["wordCount", "wordNum", "words"]),
                    fallbackKeys: ["wordCount", "wordNum", "words", "word_count", "size"],
                    variables: variables
                ),
                checkKeyWord: extractor.string(
                    from: item,
                    rule: firstRule(rule, fallback: source.ruleSearch, keys: ["checkKeyWord"]),
                    fallbackKeys: [],
                    variables: variables
                )
            )
        }
        let filtered = books.filter { passesCheckKeyWord($0.checkKeyWord, keyword: keyword) }
        if filtered.isEmpty {
            let message = candidates.isEmpty
                ? "JSON 列表规则未命中（0 项，响应 \(response.body.count) 字符）"
                : "JSON 列表命中 \(candidates.count) 项但书名或链接为空"
            return .failure(.empty(message))
        }
        return .success(Array(filtered))
    }

    private func firstRule(_ rule: SourceRule?, fallback: SourceRule? = nil, keys: [String]) -> String? {
        if let rule {
            for key in keys {
                if let value = rule.fields[key], !value.isEmpty {
                    return value
                }
            }
            if let raw = rule.raw, !raw.isEmpty, rule.fields.isEmpty {
                return raw
            }
        }
        if let fallback {
            for key in keys {
                if let value = fallback.fields[key], !value.isEmpty {
                    return value
                }
            }
            if let raw = fallback.raw, !raw.isEmpty, fallback.fields.isEmpty {
                return raw
            }
        }
        return nil
    }


    /// Legado semantics: when `ruleSearch.checkKeyWord` is configured and a
    /// keyword is available, the extracted value must contain that keyword.
    /// Rows failing the check are dropped; an empty/missing rule is permissive.
    private func passesCheckKeyWord(_ value: String?, keyword: String?) -> Bool {
        guard let keyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines), !keyword.isEmpty,
              let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return true
        }
        return value.range(of: keyword, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
