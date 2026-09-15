import Foundation
import SwiftSoup

struct ChapterListParser {
    private let htmlExtractor: HtmlRuleExtractor
    private let jsonExtractor: JSONRuleExtractor

    init(executionContext: RuleExecutionContext = RuleExecutionContext()) {
        self.htmlExtractor = HtmlRuleExtractor(executionContext: executionContext)
        self.jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
    }

    func parse(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<[BookChapter], SourceEngineError> {
        switch parsePage(source: source, book: book, response: response) {
        case .success(let page):
            return page.chapters.isEmpty ? .failure(.empty("Chapter list is empty")) : .success(page.chapters)
        case .failure(let error):
            return .failure(error)
        }
    }

    func parsePage(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<ChapterListPage, SourceEngineError> {
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
        let listRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"])
        let isJSRule = listRule.map { LegadoRuleResolver().isJavaScriptRule($0) } ?? false
        if isJSRule || ResponseFormatDetector.prefersJSON(body: normalized, headers: response.headers, rule: listRule) {
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

    private func parseHTML(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<ChapterListPage, SourceEngineError> {
        let bookMap: [String: Any] = [
            "name": book.name,
            "author": book.author ?? "",
            "coverUrl": book.coverUrl ?? "",
            "bookUrl": book.bookUrl,
            "intro": book.intro ?? ""
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
        guard let listRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"]) else {
            return .failure(.rule("ruleToc.chapterList is empty"))
        }

        do {
            let roots: [Element]
            if let initRule = htmlExtractor.firstRule(source.ruleToc, keys: ["init"]) {
                // A single Legado source may legitimately return JSON for one
                // page and HTML for a later pagination page.  JSONPath init
                // rules (for example `$.payload`) have no meaning in HTML;
                // when that selector yields no nodes, keep parsing from the
                // document root instead of turning a mixed page into an
                // empty chapter list.
                do {
                    let initialized = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: initRule)
                    roots = initialized.isEmpty
                        ? try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html")
                        : initialized
                } catch {
                    roots = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html")
                }
            } else {
                roots = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: "html")
            }
            var elements = try roots.flatMap { root in
                try htmlExtractor.select(from: root, rule: listRule, baseUrl: response.url)
            }
            if elements.isEmpty {
                let fallbackSelectors = [
                    ".listmain dd a",
                    "#list dd a",
                    ".catalog dd a",
                    ".chapters a",
                    "ul.chapter-list li a",
                    "div#list-chapterAll a",
                    ".section-box li a",
                    "#chapterlist li a",
                    ".dir-list li a",
                    "div.read-section a",
                    "#chapters-list a",
                    ".chapter-list a",
                    ".catalog-list a",
                    "#list-chapter a",
                    ".volume-list a",
                    ".mulu a",
                    "#mulu a",
                    ".dir-box a",
                    ".chapter-item a",
                    ".book-chapter-list a",
                    "#chapter_list a",
                    ".chapterlist a",
                    "div.catalog a",
                    "div.chapterlist a",
                    ".mu-box a"
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

            let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
            let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])
            let nextRule = htmlExtractor.firstRule(source.ruleToc, keys: ["nextTocUrl", "nextChapterUrl", "nextUrl"])

            var chapters = try elements.enumerated().compactMap { index, element -> BookChapter? in
                let title = try htmlExtractor.value(from: element, rule: nameRule, fallback: "a@text", baseUrl: response.url, variables: variables)
                let url = try htmlExtractor.value(from: element, rule: urlRule, fallback: "a@href", baseUrl: response.url, variables: variables)
                guard !title.isEmpty, !url.isEmpty else { return nil }
                return BookChapter(title: title, url: url, bookUrl: book.bookUrl, index: index, isVip: false)
            }
            if chapters.isEmpty && !elements.isEmpty {
                chapters = elements.enumerated().compactMap { index, element in
                    let title = (try? element.text())?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let rawHref = (try? element.attr("href"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    guard !title.isEmpty, !rawHref.isEmpty else { return nil }
                    let absUrl = htmlExtractor.absolutize(rawHref, base: response.url)
                    return BookChapter(title: title, url: absUrl, bookUrl: book.bookUrl, index: index, isVip: false)
                }
            }
            var next: String?
            for root in roots {
                next = try htmlExtractor.value(from: root, rule: nextRule, fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                if next != nil { break }
            }

            return chapters.isEmpty
                ? .failure(.empty("Chapter list is empty"))
                : .success(ChapterListPage(chapters: chapters, nextTocUrl: next))
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(source: BookSource, book: BookDetail, response: SourceResponse) -> Result<ChapterListPage, SourceEngineError> {
        let bookMap: [String: Any] = [
            "name": book.name,
            "author": book.author ?? "",
            "coverUrl": book.coverUrl ?? "",
            "bookUrl": book.bookUrl,
            "intro": book.intro ?? ""
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
        let listRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterList", "tocList", "list"])
        let isJSRule = listRule.map { LegadoRuleResolver().isJavaScriptRule($0) } ?? false

        let rootObject: Any
        if let object = ResponseFormatDetector.jsonObject(from: response.body) {
            if let initRule = htmlExtractor.firstRule(source.ruleToc, keys: ["init"]),
               let initialized = jsonExtractor.value(from: object, path: initRule, variables: variables) {
                rootObject = initialized
            } else {
                rootObject = object
            }
        } else if isJSRule {
            rootObject = response.body
        } else {
            return .failure(.rule("JSON parse failed"))
        }
        let items = jsonExtractor.list(from: rootObject, rule: listRule, variables: variables)
        let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
        let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])
        let nextRule = htmlExtractor.firstRule(source.ruleToc, keys: ["nextTocUrl", "nextChapterUrl", "nextUrl"])

        let chapters = items.enumerated().compactMap { index, item -> BookChapter? in
            let title = jsonExtractor.string(
                from: item,
                rule: nameRule,
                fallbackKeys: ["chapterName", "name", "title", "chapterTitle"],
                variables: variables
            )
            let rawUrl = jsonExtractor.string(
                from: item,
                rule: urlRule,
                fallbackKeys: ["chapterUrl", "url", "link", "id", "cid"],
                variables: variables
            )
            guard let title, let rawUrl, !title.isEmpty, !rawUrl.isEmpty else { return nil }
            return BookChapter(
                title: title,
                url: htmlExtractor.absolutize(rawUrl, base: response.url),
                bookUrl: book.bookUrl,
                index: index,
                isVip: false
            )
        }

        let next: String?
        if let dict = rootObject as? [String: Any] {
            next = jsonExtractor.string(
                from: dict,
                rule: nextRule,
                fallbackKeys: ["nextTocUrl", "nextChapterUrl", "nextUrl", "next"],
                variables: variables
            ).map { htmlExtractor.absolutize($0, base: response.url) }
        } else {
            next = nil
        }

        return chapters.isEmpty
            ? .failure(.empty("JSON chapter list is empty"))
            : .success(ChapterListPage(chapters: chapters, nextTocUrl: next))
    }
}

struct ChapterListPage: Equatable, Sendable {
    let chapters: [BookChapter]
    let nextTocUrl: String?
}
