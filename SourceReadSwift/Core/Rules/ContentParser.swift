import SwiftSoup
import Foundation

struct ContentParser {
    private let htmlExtractor: HtmlRuleExtractor
    private let jsonExtractor: JSONRuleExtractor
    private let executionContext: RuleExecutionContext

    init(executionContext: RuleExecutionContext = RuleExecutionContext()) {
        self.executionContext = executionContext
        self.htmlExtractor = HtmlRuleExtractor(executionContext: executionContext)
        self.jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
    }

    func parse(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String] = []
    ) -> Result<ChapterContent, SourceEngineError> {
        let body = ResponseFormatDetector.normalizedBody(response.body)
        let normalizedResponse = SourceResponse(
            url: response.url,
            statusCode: response.statusCode,
            headers: response.headers,
            body: body,
            data: response.data,
            encodedByteCount: response.encodedByteCount,
            bodyWasDecoded: response.bodyWasDecoded,
            contentEncodings: response.contentEncodings
        )
        let contentRuleStr = htmlExtractor.firstRule(source.ruleContent, keys: ["content", "bookContent"])
        if ResponseFormatDetector.prefersJSON(body: body, headers: response.headers, rule: contentRuleStr) {
            let jsonResult = parseJSON(source: source, chapter: chapter, response: normalizedResponse, globalPurifyRules: globalPurifyRules)
            switch jsonResult {
            case .success:
                return jsonResult
            case .failure:
                let htmlResult = parseHTML(source: source, chapter: chapter, response: normalizedResponse, globalPurifyRules: globalPurifyRules)
                if case .success = htmlResult {
                    return htmlResult
                }
                return jsonResult
            }
        } else {
            let htmlResult = parseHTML(source: source, chapter: chapter, response: normalizedResponse, globalPurifyRules: globalPurifyRules)
            switch htmlResult {
            case .success:
                return htmlResult
            case .failure:
                let jsonResult = parseJSON(source: source, chapter: chapter, response: normalizedResponse, globalPurifyRules: globalPurifyRules)
                if case .success = jsonResult {
                    return jsonResult
                }
                return htmlResult
            }
        }
    }

    private static let commonNovelContentSelectors = [
        "#content", "#chaptercontent", "#chapterContent", "#BookText", "#htmlContent",
        ".read-content", ".content", ".showtxt", "#txt", "#nr", "#nr1", "#nr_word",
        ".novelcontent", "article", "div.entry-content", ".text-content",
        "#novelcontent", "#chapter-content", "#chapter_content", "#content_text",
        ".content-wrap", "#articlecontent", "#article-content", ".readcontent",
        ".read-body", ".reading-content", ".reader-content", ".bookcontent",
        ".book-content", "#booktxt", "#booktext", "#book-text", ".yd_text2",
        "#main-text", ".post-content", "#textcontent", ".txtcontent", "#contenttxt",
        ".read_content", "div#content", "div#chaptercontent"
    ]

    private func extractFallbackParagraphs(from body: String, baseUrl: URL, title: String) -> [String] {
        if let document = try? SwiftSoup.parse(body, baseUrl.absoluteString) {
            for junk in ["script", "style", "noscript", "nav", "header", "footer", "form", "aside", ".ad", ".advert"] {
                try? document.select(junk).remove()
            }
            for selector in Self.commonNovelContentSelectors {
                if let elem = try? document.select(selector).first {
                    let html = (try? elem.html()) ?? ""
                    let clean = html
                        .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
                        .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
                    let text = ((try? SwiftSoup.parse(clean).text()) ?? (try? elem.text()) ?? "")
                    let paragraphs = splitParagraphs(text)
                    if !paragraphs.isEmpty && paragraphs.joined().count >= 30 {
                        return paragraphs
                    }
                }
            }
        }
        let article = SmartWebArticleExtractor.extract(html: body, fallbackTitle: title)
        if !article.paragraphs.isEmpty && article.paragraphs.joined().count >= 30 {
            return article.paragraphs
        }
        return []
    }

    private func parseHTML(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String]
    ) -> Result<ChapterContent, SourceEngineError> {
        let contentRule = htmlExtractor.firstRule(source.ruleContent, keys: ["content", "bookContent"])

        do {
            let rootRule = htmlExtractor.firstRule(source.ruleContent, keys: ["init"]) ?? "html"
            let root: Element?
            do {
                let initialized = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: rootRule)
                // Keep HTML pagination working when the same source uses a
                // JSONPath init path for its first page.  The JSONPath has no
                // HTML match, so fall back to the document root for HTML.
                root = (initialized.isEmpty && rootRule != "html")
                    ? try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html").first
                    : initialized.first
            } catch {
                root = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html").first
            }
            guard let root else { return .failure(.empty("正文 HTML 为空")) }
            let chapterMap: [String: Any] = [
                "title": chapter.title,
                "url": chapter.url,
                "bookUrl": chapter.bookUrl,
                "index": chapter.index
            ]
            let variables: [String: Any] = [
                "source": source,
                "chapter": chapterMap,
                "src": response.body,
                "html": response.body,
                "body": response.body,
                "baseUrl": response.url.absoluteString,
                "result": response.body
            ]

            var paragraphs: [String] = []
            if let contentRule, !contentRule.isEmpty {
                if let raw = try? htmlExtractor.value(from: root, rule: contentRule, fallback: nil, baseUrl: response.url, variables: variables) {
                    let cleaned = applyContentTransforms(raw, rule: source.ruleContent, globalPurifyRules: globalPurifyRules, variables: variables)
                    paragraphs = splitParagraphs(cleaned)
                }
            }

            // Four-level fallback: if paragraphs are empty, try common novel containers and SmartWebArticleExtractor
            if paragraphs.isEmpty {
                paragraphs = extractFallbackParagraphs(from: response.body, baseUrl: response.url, title: chapter.title)
            }

            let next = try? htmlExtractor.value(
                from: root,
                rule: htmlExtractor.firstRule(source.ruleContent, keys: ["nextContentUrl"]),
                fallback: nil,
                baseUrl: response.url,
                variables: variables
            ).nilIfEmpty

            return paragraphs.isEmpty
                ? .failure(.empty("正文解析结果为空"))
                : .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs, nextContentUrl: next))
        } catch {
            let fallback = extractFallbackParagraphs(from: response.body, baseUrl: response.url, title: chapter.title)
            if !fallback.isEmpty {
                return .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: fallback, nextContentUrl: nil))
            }
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(
        source: BookSource,
        chapter: BookChapter,
        response: SourceResponse,
        globalPurifyRules: [String]
    ) -> Result<ChapterContent, SourceEngineError> {
        guard let object = ResponseFormatDetector.jsonObject(from: response.body) else {
            return .failure(.rule("JSON 解析失败"))
        }
        let rule = source.ruleContent
        let contentRule = htmlExtractor.firstRule(rule, keys: ["content", "bookContent"])
        let chapterMap: [String: Any] = [
            "title": chapter.title,
            "url": chapter.url,
            "bookUrl": chapter.bookUrl,
            "index": chapter.index
        ]
        let variables: [String: Any] = [
            "source": source,
            "chapter": chapterMap,
            "src": response.body,
            "html": response.body,
            "body": response.body,
            "baseUrl": response.url.absoluteString,
            "result": response.body
        ]
        let rootObject: Any
        if let initRule = htmlExtractor.firstRule(rule, keys: ["init"]),
           let initialized = jsonExtractor.value(from: object, path: initRule, variables: variables) {
            rootObject = initialized
        } else {
            rootObject = object
        }
        var content: String?
        if let rule = contentRule, !rule.isEmpty {
            if let extracted = jsonExtractor.value(from: rootObject, path: rule, variables: variables) {
                let text = jsonExtractor.stringify(extracted)
                if !text.isEmpty { content = text }
            }
        }
        if content == nil, let dict = rootObject as? [String: Any] {
            content = jsonExtractor.string(
                from: dict,
                rule: contentRule,
                fallbackKeys: ["content", "bookContent", "text", "body", "chapter_content"],
                variables: variables
            )
        } else if content == nil {
            let text = jsonExtractor.stringify(rootObject)
            if !text.isEmpty { content = text }
        }
        let cleaned = applyContentTransforms(content ?? "", rule: rule, globalPurifyRules: globalPurifyRules, variables: variables)
        let paragraphs = splitParagraphs(cleaned)
        let next: String?
        if let dict = rootObject as? [String: Any] {
            next = jsonExtractor.string(
                from: dict,
                rule: htmlExtractor.firstRule(rule, keys: ["nextContentUrl"]),
                fallbackKeys: ["nextContentUrl", "nextUrl", "next"],
                variables: variables
            ).map { htmlExtractor.absolutize($0, base: response.url) }
        } else {
            next = nil
        }
        return paragraphs.isEmpty
            ? .failure(.empty("JSON \u{6b63}\u{6587}\u{89e3}\u{6790}\u{7ed3}\u{679c}\u{4e3a}\u{7a7a}"))
            : .success(ChapterContent(chapter: chapter, title: chapter.title, paragraphs: paragraphs, nextContentUrl: next))
    }

    private func splitParagraphs(_ text: String) -> [String] {
        normalizeContentText(text)
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func normalizeContentText(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "(?i)</li\\s*>", with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        output = output.replacingOccurrences(of: "&nbsp;", with: " ")
        output = output.replacingOccurrences(of: "&amp;", with: "&")
        output = output.replacingOccurrences(of: "&lt;", with: "<")
        output = output.replacingOccurrences(of: "&gt;", with: ">")
        output = output.replacingOccurrences(of: "&quot;", with: "\"")
        return output
    }

    private func applyContentTransforms(
        _ text: String,
        rule: SourceRule?,
        globalPurifyRules: [String],
        variables: [String: Any] = [:]
    ) -> String {
        var output = text
        let transformKeys = ["replaceRegex", "replace", "purify", "purifyRegex"]
        for key in transformKeys {
            guard let value = rule?.fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            output = PurifyRuleEvaluator.apply(rule: value, to: output, variables: variables, executionContext: executionContext)
        }
        output = PurifyRuleEvaluator.apply(rules: globalPurifyRules, to: output, variables: variables, executionContext: executionContext)
        return output
    }
}

