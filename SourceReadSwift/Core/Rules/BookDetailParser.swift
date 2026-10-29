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
        // Legado evaluates a JavaScript `init` before the field rules.  A JS
        // init may synthesize a JSON container from a non-JSON body, so route
        // those sources through the JSON pipeline first (the HTML parser still
        // runs as a fallback when the script yields nothing usable).
        let initRule = htmlExtractor.firstRule(source.ruleBookInfo, keys: ["init"])
        let initIsJS = initRule.map {
            LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:")
        } ?? false
        if initIsJS || ResponseFormatDetector.prefersJSON(body: normalized, headers: response.headers) {
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
            let intro = Self.introPlainText(try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["intro", "introduction"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            )) ?? book.intro
            let latest = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty
            let wordCount = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["wordCount", "words"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty
            let status = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["status", "bookStatus"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty
            let updateTime = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["updateTime", "lastUpdateTime", "update_time"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty
            let kind = try htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(rule, keys: ["kind", "category", "bookKind"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty ?? book.kind
            let rawTocRule = htmlExtractor.firstRule(rule, keys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl"])
            let tocUrl: String?
            if let rawTocRule, isURLTemplate(rawTocRule) {
                let resolved = resolveTocTemplate(rawTocRule, base: response.url, source: source, variables: variables)
                tocUrl = sanitizeSingleURL(resolved)
            } else {
                let extracted = try htmlExtractor.value(
                    from: root,
                    rule: rawTocRule,
                    fallback: nil,
                    baseUrl: response.url,
                    variables: variables
                ).nilIfEmpty
                let singleExtracted = sanitizeSingleURL(extracted)
                if let singleExtracted, isURLTemplate(singleExtracted) {
                    let resolved = resolveTocTemplate(singleExtracted, base: response.url, source: source, variables: variables)
                    tocUrl = sanitizeSingleURL(resolved)
                } else {
                    tocUrl = singleExtracted.flatMap { resolveURL($0, base: response.url) }
                }
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
                latestChapter: latest,
                wordCount: wordCount,
                status: status,
                updateTime: updateTime,
                kind: kind
            ))
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, book: SearchBook, response: SourceResponse) -> Result<BookDetail, SourceEngineError> {
        let rule = source.ruleBookInfo
        let bookMap: [String: Any] = [
            "name": book.name,
            "author": book.author ?? "",
            "coverUrl": book.coverUrl ?? "",
            "bookUrl": book.bookUrl,
            "intro": book.intro ?? "",
            "kind": book.kind ?? ""
        ]
        // `init` is a normal Legado rule and can be JavaScript.  Build the
        // same context that the field rules receive (`book`, `baseUrl`,
        // `result`, ...) before evaluating it; otherwise a JS init that reads
        // `book` or `baseUrl` fails while the field rules succeed.
        let variables: [String: Any] = [
            "source": source,
            "book": bookMap,
            "baseUrl": response.url.absoluteString,
            "result": response.body,
            "body": response.body,
            "src": response.body,
            "html": response.body
        ]
        let initRule = htmlExtractor.firstRule(rule, keys: ["init"])
        let initIsJS = initRule.map {
            LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:")
        } ?? false
        let rootObject: Any
        if let object = ResponseFormatDetector.jsonObject(from: response.body) {
            if let initRule,
               let initialized = jsonExtractor.value(from: object, path: initRule, variables: variables) {
                // JavaScript rules return strings.  When an `init` script builds a
                // JSON container (`JSON.stringify(...)`), parse it so the field
                // rules keep operating on an object instead of a string.
                rootObject = ResponseFormatDetector.jsonContainer(from: initialized)
            } else {
                rootObject = object
            }
        } else if let initRule, initIsJS,
                  let initialized = jsonExtractor.value(from: response.body, path: initRule, variables: variables) {
            // Legado runs `init` before the field rules.  A JavaScript init can
            // turn a non-JSON payload (opaque text, wrapped fragments, HTML
            // shell) into a JSON container, so do not reject the body first.
            rootObject = ResponseFormatDetector.jsonContainer(from: initialized)
        } else {
            return .failure(.rule("JSON 解析失败"))
        }

        let dict: [String: Any]
        if let direct = rootObject as? [String: Any] {
            dict = direct
        } else if let first = jsonExtractor.list(from: rootObject, rule: nil).first {
            dict = first
        } else {
            return .failure(.empty("JSON 详情为空"))
        }
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
        let intro = Self.introPlainText(jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["intro", "introduction"]),
            fallbackKeys: ["intro", "desc", "description"],
            variables: variables
        )) ?? book.intro
        let latest = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["latestChapter", "lastChapter"]),
            fallbackKeys: ["latestChapter", "lastChapter", "last"],
            variables: variables
        )?.nilIfEmpty
        let wordCount = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["wordCount", "words"]),
            fallbackKeys: ["wordCount", "words", "word_count"],
            variables: variables
        )?.nilIfEmpty
        let status = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["status", "bookStatus"]),
            fallbackKeys: ["status", "bookStatus", "serialize"],
            variables: variables
        )?.nilIfEmpty
        let updateTime = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["updateTime", "lastUpdateTime", "update_time"]),
            fallbackKeys: ["updateTime", "lastUpdateTime", "update_time", "lastUpdate"],
            variables: variables
        )?.nilIfEmpty
        let kind = jsonExtractor.string(
            from: dict,
            rule: htmlExtractor.firstRule(rule, keys: ["kind", "category", "bookKind"]),
            fallbackKeys: ["kind", "category", "bookKind", "tags"],
            variables: variables
        )?.nilIfEmpty ?? book.kind
        var jsonVariables = variables
        jsonVariables["result"] = dict
        jsonVariables["data"] = dict
        jsonVariables["json"] = dict
        let rawTocRule = htmlExtractor.firstRule(rule, keys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl"])
        let tocUrl: String?
        if let rawTocRule, isURLTemplate(rawTocRule) {
            let resolved = resolveTocTemplate(rawTocRule, base: response.url, source: source, variables: jsonVariables)
            tocUrl = sanitizeSingleURL(resolved)
        } else {
            let rawTocUrl = jsonExtractor.string(
                from: dict,
                rule: rawTocRule,
                fallbackKeys: ["tocUrl", "chapterUrl", "catalogUrl", "chapterListUrl", "toc_url", "chapter_url"],
                variables: variables
            )?.nilIfEmpty
            if let singleTocUrl = sanitizeSingleURL(rawTocUrl) {
                if isURLTemplate(singleTocUrl) {
                    let resolved = resolveTocTemplate(singleTocUrl, base: response.url, source: source, variables: jsonVariables)
                    tocUrl = sanitizeSingleURL(resolved)
                } else {
                    tocUrl = resolveURL(singleTocUrl, base: response.url)
                }
            } else {
                tocUrl = nil
            }
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
            latestChapter: latest,
            wordCount: wordCount,
            status: status,
            updateTime: updateTime,
            kind: kind
        ))
    }

    /// Intro rules frequently end in `@html`; Legado shows that markup as
    /// rich text, while this app renders plain text.  Keep line breaks from
    /// `<br>` / `</p>` / `</div>` and drop the remaining tags so a book card
    /// never displays literal `<div class="intro">`.
    private static func introPlainText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.contains("<") else { return trimmed }
        var text = trimmed
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
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
            || trimmed.contains("@js:")
            || trimmed.contains("@get:")
            || (trimmed.contains("{{") && trimmed.contains("}}"))
            || (trimmed.lowercased().contains("%7b%7b") && trimmed.lowercased().contains("%7d%7d"))
    }

    private func resolveTocTemplate(_ template: String, base: URL, source: BookSource, variables: [String: Any]) -> String {
        var resolved = template
        let pattern = #"(?i)@get:\{?([^}@]*)?\}?"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            let mText = NSMutableString(string: resolved)
            let matches = regex.matches(in: resolved, range: NSRange(location: 0, length: mText.length))
            for match in matches.reversed() {
                guard match.numberOfRanges > 1 else { continue }
                let key = mText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                let val = executionContext.get(key)
                mText.replaceCharacters(in: match.range(at: 0), with: val)
            }
            resolved = mText as String
        }
        let dynamicResolved = DynamicURLResolver.resolve(
            resolved,
            baseUrl: base.absoluteString,
            source: source,
            variables: variables,
            context: executionContext
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if dynamicResolved.isEmpty || dynamicResolved.hasPrefix("@js:") || dynamicResolved.hasPrefix("<js>") {
            return ""
        }

        return resolveURL(dynamicResolved, base: base) ?? dynamicResolved
    }

    private func sanitizeSingleURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let (urlPart, suffixPart) = SearchURLResolver.splitURLAndDirectiveSuffix(raw)
        let firstLine = urlPart
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let firstLine, !firstLine.isEmpty else { return nil }
        return firstLine + suffixPart
    }

    private func resolveURL(_ text: String, base: URL) -> String? {
        guard let sanitized = sanitizeSingleURL(text) else { return nil }
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Foundation must only see the URL. Feeding the request options to
        // URL(string:) percent-encodes JSON braces/quotes into the address and
        // loses POST/bodyJs when the next stage reparses the directive.
        let (urlPart, suffixPart) = SearchURLResolver.splitURLAndDirectiveSuffix(trimmed)
        if urlPart.hasPrefix("@js:") || urlPart.hasPrefix("<js>") {
            return nil
        }
        if let absolute = URL(string: urlPart), absolute.scheme != nil {
            return absolute.absoluteString + suffixPart
        }
        guard let relative = URL(string: urlPart, relativeTo: base) else { return nil }
        return relative.absoluteURL.absoluteString + suffixPart
    }
}
