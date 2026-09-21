import Foundation
import SwiftSoup

struct BookDetailParser {
    private let htmlExtractor: HtmlRuleExtractor
    private let jsonExtractor: JSONRuleExtractor
    private let executionContext: RuleExecutionContext

    init(executionContext: RuleExecutionContext = RuleExecutionContext()) {
        self.htmlExtractor = HtmlRuleExtractor(executionContext: executionContext)
        self.jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
        self.executionContext = executionContext
    }

    func parse(source: BookSource, book: SearchBook, response: SourceResponse) -> Result<BookDetail, SourceEngineError> {
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
        if ResponseFormatDetector.prefersJSON(body: normalized, headers: response.headers) {
            let jsonResult = parseJSON(source: source, book: book, response: normalizedResponse)
            switch jsonResult {
            case .success:
                return jsonResult
            case .failure:
                let htmlResult = parseHTML(source: source, book: book, response: normalizedResponse)
                if case .success = htmlResult {
                    return htmlResult
                }
                return jsonResult
            }
        } else {
            let htmlResult = parseHTML(source: source, book: book, response: normalizedResponse)
            switch htmlResult {
            case .success:
                return htmlResult
            case .failure:
                let jsonResult = parseJSON(source: source, book: book, response: normalizedResponse)
                if case .success = jsonResult {
                    return jsonResult
                }
                return htmlResult
            }
        }
    }

    private func parseHTML(source: BookSource, book: SearchBook, response: SourceResponse) -> Result<BookDetail, SourceEngineError> {
        do {
            let document = try SwiftSoup.parse(response.body, response.url.absoluteString)
            let rule = source.ruleBookInfo
            let root: Element
            if let initRule = htmlExtractor.firstRule(rule, keys: ["init"]),
               let initialized = try htmlExtractor.select(from: document, rule: initRule, baseUrl: response.url).first {
                root = initialized
            } else {
                root = document
            }
            let bookMap: [String: Any] = [
                "name": book.name,
                "author": book.author ?? "",
                "coverUrl": book.coverUrl ?? "",
                "bookUrl": book.bookUrl,
                "intro": book.intro ?? "",
                "kind": book.kind ?? ""
            ]
            let variables: [String: Any] = [
                "source": source,
                "book": bookMap,
                "baseUrl": response.url.absoluteString,
                "result": response.body,
                "body": response.body,
                "src": response.body,
                "html": response.body
            ]
            let name = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["name", "bookName"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.name
            let author = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["author"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.author
            let cover = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["coverUrl", "cover"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.coverUrl
            let intro = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["intro", "introduction"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.intro
            let latest = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty
            let rawTocRule = htmlExtractor.firstRule(rule, keys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl"])
            let tocUrl: String?
            if let rawTocRule, isURLTemplate(rawTocRule) {
                let resolved = resolveTocTemplate(rawTocRule, base: response.url, source: source, variables: variables)
                tocUrl = resolved.nilIfEmpty
            } else {
                tocUrl = try htmlExtractor.value(
                    from: root,
                    rule: rawTocRule,
                    fallback: nil,
                    baseUrl: response.url,
                    variables: variables
                ).nilIfEmpty
            }

            return .success(BookDetail(
                name: name,
                author: author,
                coverUrl: cover,
                bookUrl: book.bookUrl,
                tocUrl: tocUrl,
                sourceName: source.bookSourceName,
                sourceUrl: source.bookSourceUrl,
                intro: intro,
                latestChapter: latest
            ))
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, book: SearchBook, response: SourceResponse) -> Result<BookDetail, SourceEngineError> {
        guard let object = ResponseFormatDetector.jsonObject(from: response.body) else {
            return .failure(.rule("JSON 解析失败"))
        }
        let rootObject: Any
        if let initRule = htmlExtractor.firstRule(source.ruleBookInfo, keys: ["init"]),
           let initialized = jsonExtractor.value(from: object, path: initRule, variables: ["source": source]) {
            rootObject = initialized
        } else {
            rootObject = object
        }

        let dict: [String: Any]
        if let direct = rootObject as? [String: Any] {
            dict = direct
        } else if let first = jsonExtractor.list(from: rootObject, rule: nil).first {
            dict = first
        } else {
            return .failure(.empty("JSON 详情为空"))
        }

        let rule = source.ruleBookInfo
        let bookMap: [String: Any] = [
            "name": book.name,
            "author": book.author ?? "",
            "coverUrl": book.coverUrl ?? "",
            "bookUrl": book.bookUrl,
            "intro": book.intro ?? "",
            "kind": book.kind ?? ""
        ]
        let variables: [String: Any] = [
            "source": source,
            "book": bookMap,
            "baseUrl": response.url.absoluteString,
            "result": response.body,
            "body": response.body,
            "src": response.body,
            "html": response.body
        ]
        let name = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["name", "bookName"]),
            fallbackKeys: ["name", "bookName", "title", "book_name"],
            variables: variables
        )?.nilIfEmpty ?? book.name
        let author = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["author"]),
            fallbackKeys: ["author", "writer"],
            variables: variables
        )?.nilIfEmpty ?? book.author
        let cover = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["coverUrl", "cover"]),
            fallbackKeys: ["cover", "coverUrl", "img", "image"],
            variables: variables
        )?.nilIfEmpty ?? book.coverUrl
        let intro = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["intro", "introduction"]),
            fallbackKeys: ["intro", "desc", "description"],
            variables: variables
        )?.nilIfEmpty ?? book.intro
        let latest = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
            fallbackKeys: ["latestChapter", "lastChapter", "last"],
            variables: variables
        )?.nilIfEmpty
        let rawTocRule = htmlExtractor.firstRule(rule, keys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl"])
        let tocUrl: String?
        if let rawTocRule, isURLTemplate(rawTocRule) {
            let resolved = resolveTocTemplate(rawTocRule, base: response.url, source: source, variables: variables)
            tocUrl = resolved.nilIfEmpty
        } else {
            let rawTocUrl = jsonExtractor.string(
                from: dict,
                rule: rawTocRule,
                fallbackKeys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl", "toc_url", "chapter_url"],
                variables: variables
            )?.nilIfEmpty
            tocUrl = rawTocUrl.flatMap { resolveURL($0, base: response.url) }
        }

        return .success(BookDetail(
            name: name,
            author: author,
            coverUrl: cover,
            bookUrl: book.bookUrl,
            tocUrl: tocUrl,
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: intro,
            latestChapter: latest
        ))
    }

    private func isURLTemplate(_ rule: String) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(".") || trimmed.hasPrefix("#") || trimmed.hasPrefix("//")
            || trimmed.hasPrefix("tag.") || trimmed.hasPrefix("class.") || trimmed.hasPrefix("id.")
            || trimmed.hasPrefix("center") || trimmed.hasPrefix("div") || trimmed.hasPrefix("ul")
            || trimmed.hasPrefix("table") || trimmed.hasPrefix("p") || trimmed.hasPrefix("a:")
            || trimmed.hasPrefix("a@") || trimmed.hasPrefix("span") {
            return false
        }
        return trimmed.hasPrefix("http://")
            || trimmed.hasPrefix("https://")
            || trimmed.hasPrefix("@js:")
            || trimmed.hasPrefix("<js>")
            || trimmed.contains("@get:")
            || (trimmed.contains("{{") && trimmed.contains("}}"))
    }

    private func resolveTocTemplate(_ template: String, base: URL, source: BookSource, variables: [String: Any]) -> String {
        var resolved = template
        let pattern = #"(?i)@get:\{?([^}@]*)?\}?"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let matches = regex.matches(in: resolved, range: NSRange(resolved.startIndex..<resolved.endIndex, in: resolved)).reversed()
            for match in matches {
                guard let fullRange = Range(match.range(at: 0), in: resolved),
                      let keyRange = Range(match.range(at: 1), in: resolved) else { continue }
                let key = String(resolved[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = executionContext.get(key)
                resolved.replaceSubrange(fullRange, with: val)
            }
        }
        let dynamicResolved = DynamicURLResolver.resolve(
            resolved,
            baseUrl: base.absoluteString,
            source: source,
            variables: variables,
            context: executionContext
        )
        return resolveURL(dynamicResolved, base: base) ?? dynamicResolved
    }

    private func resolveURL(_ text: String, base: URL) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute.absoluteString
        }
        return URL(string: trimmed, relativeTo: base)?.absoluteURL.absoluteString
    }
}
