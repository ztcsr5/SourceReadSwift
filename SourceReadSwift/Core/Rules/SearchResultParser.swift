import Foundation
import SwiftSoup

struct SearchResultParser {
    private let htmlExtractor: HtmlRuleExtractor
    private let jsonExtractor: JSONRuleExtractor
    private let executionContext: RuleExecutionContext
    /// Called after a result row's `bookUrl` rule runs, carrying the variables
    /// that rule wrote.  Detail/TOC/content replay the delta so an aggregator
    /// that evaluates `java.put('id', ...)` for every row does not leave the
    /// last row's id behind for the row the user actually tapped.
    var onBookVariables: ((String, [String: String]) -> Void)?

    init(executionContext: RuleExecutionContext = RuleExecutionContext()) {
        self.executionContext = executionContext
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

        // Legado list-level AllInOne: `bookList` may be `:regex` over the raw
        // body. Group 1 is the detail URL, group 2 the title; other fields
        // address their own capture groups through `$1`/`$2`.
        if let allInOne = LegadoAllInOneRegex.rule(from: listRule) {
            var books: [SearchBook] = []
            for row in LegadoAllInOneRegex.rows(allInOne, body: response.body) {
                let name = LegadoAllInOneRegex.field(firstRule(rule, fallback: source.ruleSearch, keys: ["name", "bookName"]), row: row, defaultGroup: 2)
                let rawURL = LegadoAllInOneRegex.field(firstRule(rule, fallback: source.ruleSearch, keys: ["bookUrl", "url"]), row: row, defaultGroup: 1)
                guard !name.isEmpty, !rawURL.isEmpty else { continue }
                let absBookUrl = htmlExtractor.absolutize(rawURL, base: response.url)
                guard !absBookUrl.isEmpty, !absBookUrl.lowercased().hasPrefix("javascript:") else { continue }
                func optionalField(_ keys: [String]) -> String? {
                    guard let ruleText = firstRule(rule, fallback: source.ruleSearch, keys: keys) else { return nil }
                    return LegadoAllInOneRegex.field(ruleText, row: row, defaultGroup: 0).nilIfEmpty
                }
                books.append(SearchBook(
                    name: name,
                    author: optionalField(["author"]),
                    coverUrl: optionalField(["coverUrl", "cover"]),
                    bookUrl: absBookUrl,
                    sourceName: source.bookSourceName,
                    sourceUrl: source.bookSourceUrl,
                    intro: optionalField(["intro"]),
                    kind: optionalField(["kind"]),
                    lastChapter: optionalField(["lastChapter"]),
                    wordCount: optionalField(["wordCount", "wordNum", "words"]),
                    checkKeyWord: optionalField(["checkKeyWord"])
                ))
            }
            return .success(books)
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

                let variablesBeforeBookURL = executionContext.persistentSnapshot()
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
                let variablesAfterBookURL = executionContext.persistentSnapshot()
                let bookVariableDelta = variablesAfterBookURL.filter { variablesBeforeBookURL[$0.key] != $0.value }
                if !bookVariableDelta.isEmpty {
                    onBookVariables?(absBookUrl, bookVariableDelta)
                }

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
                let jsError = executionContext.currentJavaScriptError
                let message = elements.isEmpty
                    ? (jsError.map { "搜索规则 JS 异常：\($0)" }
                        ?? "搜索列表规则未命中（0 个节点，响应 \(response.body.count) 字符）")
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
            let variablesBeforeBookURL = executionContext.persistentSnapshot()
            let bookUrlRule = firstRule(rule, fallback: source.ruleSearch, keys: ["bookUrl", "url"])
            var bookURLFallbackKeys = ["bookUrl", "url", "link", "book_url"]
            // A bare `id` is not a book URL.  Only sources without any
            // bookUrl rule rely on it (their request builder appends the id).
            // When the rule exists but its `@js` failed, the old fallback
            // silently produced `https://api-bc.wtzw.com/1784900` and every
            // detail request 404'd (七猫).  Keep the failure visible instead.
            if (bookUrlRule?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                bookURLFallbackKeys.append("id")
            }
            let url = extractor.string(
                from: item,
                rule: bookUrlRule,
                fallbackKeys: bookURLFallbackKeys,
                variables: variables
            )
            if url == nil, let bookUrlRule, bookUrlRule.contains("@js:") {
                executionContext.recordJavaScriptError(
                    "bookUrl 规则未产出 URL（\(source.bookSourceName)）"
                )
            }
            let variablesAfterBookURL = executionContext.persistentSnapshot()
            let bookVariableDelta = variablesAfterBookURL.filter { variablesBeforeBookURL[$0.key] != $0.value }
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
            if !bookVariableDelta.isEmpty {
                onBookVariables?(absBookUrl, bookVariableDelta)
            }
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
        let filtered = books
        if filtered.isEmpty {
            let jsError = executionContext.currentJavaScriptError
            let message = candidates.isEmpty
                ? (jsError.map { "搜索规则 JS 异常：\($0)" }
                    ?? "JSON 列表规则未命中（0 项，响应 \(response.body.count) 字符；结构 \(Self.jsonShapeHint(response.body))）")
                : "JSON 列表命中 \(candidates.count) 项但书名或链接为空"
            return .failure(.empty(message))
        }
        return .success(Array(filtered))
    }


    /// When a JSON list rule matches nothing, the raw body is still the only
    /// clue the operator has.  Listing the top-level keys turns "0 items" into
    /// an actionable hint (`{"data":{"list":...}}` vs `{"books":...}`) without
    /// having to re-run the request by hand.
    static func jsonShapeHint(_ body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            let head = trimmed.prefix(60).replacingOccurrences(of: "\n", with: " ")
            return "非 JSON：\(head)"
        }
        if let dict = object as? [String: Any] {
            let keys = dict.keys.sorted().prefix(8).joined(separator: ",")
            return "{ \(keys) }"
        }
        if let array = object as? [Any] {
            if let first = array.first as? [String: Any] {
                return "[\(array.count)] item{ \(first.keys.sorted().prefix(8).joined(separator: ",")) }"
            }
            return "[\(array.count)]"
        }
        return "标量"
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


}
