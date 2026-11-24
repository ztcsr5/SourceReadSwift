import Foundation
import SwiftSoup

struct ChapterListParser {
    private let htmlExtractor: HtmlRuleExtractor
    private let jsonExtractor: JSONRuleExtractor
    private let executionContext: RuleExecutionContext

    private enum HTMLChapterRow {
        case chapter(BookChapter)
        case volumeMarker
        case missingFields(isTitleMissing: Bool, isLinkMissing: Bool)
        case filteredLink

        var chapter: BookChapter? {
            if case .chapter(let chapter) = self { return chapter }
            return nil
        }
    }

    private struct HTMLCatalogEvidence {
        var missingTitle = 0
        var missingLink = 0
        var filteredLink = 0
        var volumeMarkers = 0

        mutating func record(_ row: HTMLChapterRow) {
            switch row {
            case .chapter: break
            case .volumeMarker: volumeMarkers += 1
            case .filteredLink: filteredLink += 1
            case .missingFields(let isTitleMissing, let isLinkMissing):
                if isTitleMissing { missingTitle += 1 }
                if isLinkMissing { missingLink += 1 }
            }
        }

        var summary: String {
            "标题为空 \(missingTitle)，链接为空 \(missingLink)，链接被过滤 \(filteredLink)，卷标题 \(volumeMarkers)"
        }
    }

    init(executionContext: RuleExecutionContext = RuleExecutionContext()) {
        self.executionContext = executionContext
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

    func parsePage(
        source: BookSource,
        book: BookDetail,
        response: SourceResponse,
        inheritedVolume: String? = nil
    ) -> Result<ChapterListPage, SourceEngineError> {
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
        let isJSRule = listRule.map { LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:") } ?? false
        let htmlScript = isJSRule && normalized.hasPrefix("<") && normalized.prefix(4).lowercased() != "<pre"
            && htmlExtractor.firstRule(source.ruleToc, keys: ["init"]) == nil
            && listRule.map(jsonExtractor.hasScriptAfterHTMLSelector) == true ? listRule : nil
        let prefersJSON = isJSRule || ResponseFormatDetector.prefersJSON(body: normalized, headers: response.headers, rule: listRule)
        // 空页也算一次机会：目录为空时换另一套提取器再试一次，
        // 避免 92 条「Chapter list is empty」其实是另一套规则能解析的。
        if prefersJSON {
            if isJSRule {
                executionContext.recordScriptRequestFailure(nil)
                executionContext.clearJavaScriptError()
            }
            let jsonResult = parseJSON(source: source, book: book, response: normalizedResponse,
                                       catalog: (inheritedVolume, htmlScript))
            // Parser fallback must not hide an unsuccessful script request as a selector mismatch.
            if isJSRule, case .failure = jsonResult, let requestFailure = executionContext.latestScriptRequestFailure {
                return .failure(requestFailure)
            }
            if isJSRule, case .failure = jsonResult, let scriptError = executionContext.currentJavaScriptError {
                return .failure(.javascript("目录规则 JS 异常：\(scriptError)"))
            }
            // A script may have fetched another page or explicitly filtered out all rows.
            if htmlScript != nil { return jsonResult }
            switch jsonResult {
            case .success(let page) where !page.chapters.isEmpty:
                return jsonResult
            case .success:
                let htmlResult = parseHTML(source: source, book: book, response: normalizedResponse, inheritedVolume: inheritedVolume)
                if case .success(let htmlPage) = htmlResult, !htmlPage.chapters.isEmpty {
                    return htmlResult
                }
                return jsonResult
            case .failure:
                let htmlResult = parseHTML(source: source, book: book, response: normalizedResponse, inheritedVolume: inheritedVolume)
                if case .success = htmlResult {
                    return htmlResult
                }
                return jsonResult
            }
        } else {
            let htmlResult = parseHTML(source: source, book: book, response: normalizedResponse, inheritedVolume: inheritedVolume)
            switch htmlResult {
            case .success(let page) where !page.chapters.isEmpty:
                return htmlResult
            case .success:
                let jsonResult = parseJSON(source: source, book: book, response: normalizedResponse, catalog: (inheritedVolume, nil))
                if case .success(let jsonPage) = jsonResult, !jsonPage.chapters.isEmpty {
                    return jsonResult
                }
                return htmlResult
            case .failure:
                let jsonResult = parseJSON(source: source, book: book, response: normalizedResponse, catalog: (inheritedVolume, nil))
                if case .success = jsonResult {
                    return jsonResult
                }
                return htmlResult
            }
        }
    }

    private func directoryBook(source: BookSource, book: BookDetail) -> LegadoSearchBookBridge {
        if let current = executionContext.value(for: "toc.book") as? LegadoSearchBookBridge,
           current.bookUrl == book.bookUrl, current.origin == book.sourceUrl {
            return current
        }
        let bridge = LegadoSearchBookBridge(book: book)
        bridge.initializeMediaKindIfNeeded(source.sourceKind)
        // Reuse the same authored book across TOC fields and pagination.
        executionContext.setValue(bridge, for: "toc.book")
        return bridge
    }

    private func mediaOverride(in variables: [String: Any], book: BookDetail) -> BookSourceKind? {
        guard let source = variables["source"] as? BookSource,
              let bridge = variables["book"] as? LegadoSearchBookBridge,
              let kind = bridge.mediaKind,
              bridge.hasExplicitType || kind != (book.mediaKind ?? source.sourceKind) else { return nil }
        return kind
    }

    private func parseHTML(
        source: BookSource,
        book: BookDetail,
        response: SourceResponse,
        inheritedVolume: String?
    ) -> Result<ChapterListPage, SourceEngineError> {
        let bookMap = directoryBook(source: source, book: book)
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

        // Legado list-level AllInOne: `chapterList` may be `:regex` over the raw
        // body instead of a CSS selector. Every match is one chapter row and the
        // field rules address the capture groups (`$1` URL, `$2` name). The
        // 997-source corpus has no such source, but hand-written sources and the
        // official syntax guide both use it.
        if let allInOne = LegadoAllInOneRegex.rule(from: listRule) {
            let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
            let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])
            var chapters: [BookChapter] = []
            for row in LegadoAllInOneRegex.rows(allInOne, body: response.body) {
                let title = LegadoAllInOneRegex.field(nameRule, row: row, defaultGroup: 2)
                let rawURL = LegadoAllInOneRegex.field(urlRule, row: row, defaultGroup: 1)
                guard let cleaned = sanitizeSingleChapterURL(rawURL) else { continue }
                let absURL = htmlExtractor.absolutize(cleaned, base: response.url)
                guard isValidChapter(title: title, url: absURL, page: (response.url, false), bookURL: book.bookUrl) else { continue }
                chapters.append(BookChapter(
                    title: title,
                    url: absURL,
                    bookUrl: book.bookUrl,
                    index: chapters.count,
                    volumeName: inheritedVolume,
                    mediaKind: mediaOverride(in: variables, book: book),
            useReplaceRule: (variables["book"] as? LegadoSearchBookBridge)?.useReplaceRuleOverride
                ))
            }
            return .success(ChapterListPage(chapters: chapters, nextTocUrl: nil, trailingVolume: inheritedVolume))
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
                    let initialized = try htmlExtractor.select(response.body, baseUrl: response.url, listRule: initRule, variables: variables)
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
                try htmlExtractor.select(from: root, rule: listRule, baseUrl: response.url, variables: variables)
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
                    ".dir-list a",
                    ".dir-list dd a",
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

            let isVolumeRule = source.ruleToc?.fields["isVolume"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            var currentVolume: String? = inheritedVolume
            var chapters: [BookChapter] = []
            var evidence = HTMLCatalogEvidence()
            for element in elements {
                let row = projectChapter(
                    from: element,
                    index: chapters.count,
                    book: book,
                    response: response,
                    variables: variables,
                    nameRule: nameRule,
                    urlRule: urlRule,
                    tocRule: source.ruleToc,
                    isVolumeRule: isVolumeRule,
                    currentVolume: &currentVolume
                )
                if let chapter = row.chapter {
                    chapters.append(chapter)
                } else {
                    evidence.record(row)
                }
            }
            if chapters.isEmpty && !elements.isEmpty {
                chapters = elements.enumerated().compactMap { index, element in
                    projectChapter(
                        from: element,
                        index: index,
                        book: book,
                        response: response,
                        variables: variables,
                        nameRule: nameRule,
                        urlRule: urlRule,
                        tocRule: source.ruleToc,
                        isVolumeRule: isVolumeRule,
                        currentVolume: &currentVolume,
                        fallbackToAnchor: true
                    ).chapter
                }
            }
            if chapters.isEmpty {
                // Some single-track sources intentionally have only a title
                // row. Their content rule runs on the same request as the TOC.
                if urlRule == nil, isVolumeRule == nil, elements.count == 1, let element = elements.first {
                    var variables = variables
                    variables["result"] = LegadoElementBridge(element: element, baseURL: response.url.absoluteString)
                    let title = try htmlExtractor.value(from: element, rule: nameRule, fallback: "text",
                                                        baseUrl: response.url, variables: variables)
                    if let chapter = singleMediaChapter(title: title, variables: variables, book: book, response: response) {
                        return .success(ChapterListPage(chapters: [chapter], nextTocUrl: nil, trailingVolume: inheritedVolume))
                    }
                }
                var candidateSelectors: [String] = []
                if listRule.contains(".1") {
                    candidateSelectors.append(listRule.replacingOccurrences(of: ".1", with: ".0"))
                    candidateSelectors.append(listRule.replacingOccurrences(of: ".1", with: ""))
                }
                candidateSelectors.append(contentsOf: [
                    ".listmain dd a",
                    "#list dd a",
                    ".catalog dd a",
                    ".chapters a",
                    "ul.chapter-list li a",
                    "div#list-chapterAll a",
                    ".section-box li a",
                    "#chapterlist li a",
                    ".dir-list li a",
                    ".dir-list a",
                    ".dir-list dd a",
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
                ])
                for sel in candidateSelectors {
                    guard let altElements = try? roots.flatMap({ root in
                        try htmlExtractor.select(from: root, rule: sel, baseUrl: response.url)
                    }), !altElements.isEmpty else { continue }
                    let altChapters = altElements.enumerated().compactMap { index, element -> BookChapter? in
                        projectChapter(
                            from: element,
                            index: index,
                            book: book,
                            response: response,
                            variables: variables,
                            nameRule: nameRule,
                            urlRule: urlRule,
                            tocRule: source.ruleToc,
                            isVolumeRule: isVolumeRule,
                            currentVolume: &currentVolume
                        ).chapter
                    }
                    if !altChapters.isEmpty {
                        chapters = altChapters
                        break
                    }
                }
            }
            // Volume rows are consumed rather than emitted, so renumber the
            // surviving rows to keep `index` contiguous on every HTML path.
            if !chapters.isEmpty {
                chapters = chapters.enumerated().map { offset, chapter in
                    chapter.withIndex(offset)
                }
            }
            var next: String?
            for root in roots {
                let rawNext = try htmlExtractor.value(from: root, rule: nextRule, fallback: nil, baseUrl: response.url, variables: variables).nilIfEmpty
                next = sanitizeNextTocURL(rawNext, currentURL: response.url)
                if next != nil { break }
            }

            if chapters.isEmpty {
                let jsError = executionContext.currentJavaScriptError
                let message = elements.isEmpty
                    ? (jsError.map { "目录规则 JS 异常：\($0)" }
                        ?? "目录规则未命中（0 个节点，响应 \(response.body.count) 字符）")
                    : "目录规则命中 \(elements.count) 个节点但无可用章节（\(evidence.summary)）"
                return .failure(.empty(message))
            }
            return .success(ChapterListPage(chapters: chapters, nextTocUrl: next, trailingVolume: currentVolume))
        } catch {
            return .failure(.rule(error.localizedDescription))
        }
    }

    private func parseJSON(
        source: BookSource,
        book: BookDetail,
        response: SourceResponse,
        catalog: (inheritedVolume: String?, htmlScript: String?)
    ) -> Result<ChapterListPage, SourceEngineError> {
        let bookMap = directoryBook(source: source, book: book)
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
        let isJSRule = listRule.map { LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:") } ?? false

        let initRule = htmlExtractor.firstRule(source.ruleToc, keys: ["init"])
        let initIsJS = initRule.map {
            LegadoRuleResolver().isJavaScriptRule($0) || $0.contains("<js>") || $0.contains("@js:")
        } ?? false
        let rootObject: Any
        if catalog.htmlScript != nil {
            rootObject = response.body
        } else if let object = ResponseFormatDetector.jsonObject(from: response.body) {
            if let initRule,
               let initialized = jsonExtractor.value(from: object, path: initRule, variables: variables) {
                rootObject = ResponseFormatDetector.jsonContainer(from: initialized)
            } else {
                rootObject = object
            }
        } else if let initRule, initIsJS,
                  let initialized = jsonExtractor.value(from: response.body, path: initRule, variables: variables) {
            // See SearchResultParser: Legado runs `init` before field rules,
            // and a JS init can build JSON from a non-JSON payload.
            rootObject = ResponseFormatDetector.jsonContainer(from: initialized)
        } else if isJSRule {
            rootObject = response.body
        } else {
            return .failure(.rule("JSON parse failed"))
        }
        let items: [Any]
        let htmlRoot: Element?
        if let htmlScript = catalog.htmlScript {
            do {
                let document = try SwiftSoup.parse(response.body, response.url.absoluteString)
                htmlRoot = document
                let selected = try jsonExtractor.selectionValue(from: document, rule: htmlScript, variables: variables) ?? NSNull()
                if let elements = try jsonExtractor.selectionElements(selected, baseURL: response.url.absoluteString) {
                    items = elements
                } else if let mixed = selected as? [Any] {
                    items = mixed
                } else {
                    items = jsonExtractor.list(from: selected, rule: nil)
                }
            } catch let error as SourceEngineError {
                return .failure(error)
            } catch {
                return .failure(.rule(error.localizedDescription))
            }
        } else {
            items = jsonExtractor.list(from: rootObject, rule: listRule, variables: variables)
            htmlRoot = nil
        }
        let nameRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterName", "name", "title"])
        let urlRule = htmlExtractor.firstRule(source.ruleToc, keys: ["chapterUrl", "url"])
        let nextRule = htmlExtractor.firstRule(source.ruleToc, keys: ["nextTocUrl", "nextChapterUrl", "nextUrl"])

        let isExplicitSingleChapter = isJSRule && items.count == 1 && nameRule != nil && urlRule != nil
            && nextRule == nil && htmlExtractor.firstRule(source.ruleContent, keys: ["content", "bookContent"]) != nil
        let isVolumeRule = source.ruleToc?.fields["isVolume"]?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        var currentVolume: String? = catalog.inheritedVolume
        var chapters: [BookChapter] = []
        var evidence = HTMLCatalogEvidence()
        var singleTitleWithoutURL: String?
        for item in items {
            if let element = (item as? LegadoElementBridge)?.element ?? (item as? Element) {
                let row = projectChapter(from: element, index: chapters.count, book: book, response: response,
                    variables: variables, nameRule: nameRule, urlRule: urlRule, tocRule: source.ruleToc,
                    isVolumeRule: isVolumeRule, currentVolume: &currentVolume)
                if let chapter = row.chapter {
                    chapters.append(chapter)
                } else {
                    evidence.record(row)
                }
                continue
            }
            let title = jsonExtractor.string(
                from: item,
                rule: nameRule,
                fallbackKeys: ["chapterName", "name", "title", "chapterTitle", "n", "text"],
                variables: variables
            ) ?? ""
            let volumeRaw = jsonExtractor.string(
                from: item,
                rule: isVolumeRule,
                fallbackKeys: ["isVolume"],
                variables: variables
            )
            if isVolumeValue(volumeRaw) {
                // See the HTML path: volume rows become the `volumeName` of
                // every following chapter instead of a fake chapter row.
                if !title.isEmpty { currentVolume = title }
                continue
            }
            let rawUrl = jsonExtractor.string(
                from: item,
                rule: urlRule,
                fallbackKeys: ["chapterUrl", "url", "link", "id", "cid", "u", "href"],
                variables: variables
            ).flatMap(sanitizeSingleChapterURL)
            if title.isEmpty { evidence.missingTitle += 1 }
            if rawUrl?.isEmpty != false {
                evidence.missingLink += 1
                if items.count == 1 { singleTitleWithoutURL = title }
            }
            guard !title.isEmpty, let rawUrl, !rawUrl.isEmpty else { continue }
            let absUrl = htmlExtractor.absolutize(rawUrl, base: response.url)
            let allowsSamePage = isExplicitSingleChapter && absUrl == response.url.absoluteString
            guard isValidChapter(title: title, url: absUrl, page: (response.url, allowsSamePage), bookURL: book.bookUrl) else {
                evidence.filteredLink += 1
                continue
            }
            let vipRaw = jsonExtractor.string(
                from: item,
                rule: htmlExtractor.firstRule(source.ruleToc, keys: ["isVip", "vip"]),
                fallbackKeys: ["isVip", "vip", "vipFlag"],
                variables: variables
            )?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isVip = vipRaw.map { !["", "false", "0", "no", "free"].contains($0) } ?? false
            let payRaw = jsonExtractor.string(
                from: item,
                rule: htmlExtractor.firstRule(source.ruleToc, keys: ["isPay", "paid", "purchased"]),
                fallbackKeys: ["isPay", "paid", "purchased"],
                variables: variables
            )
            chapters.append(BookChapter(
                title: title,
                url: absUrl,
                bookUrl: book.bookUrl,
                index: chapters.count,
                isVip: isVip,
                isPay: optionalBooleanFlag(payRaw),
                updateTime: jsonExtractor.string(
                    from: item,
                    rule: htmlExtractor.firstRule(source.ruleToc, keys: ["updateTime", "update", "time"]),
                    fallbackKeys: ["updateTime", "update_time", "time", "lastUpdate"],
                    variables: variables
                ),
                volumeName: jsonExtractor.string(
                    from: item,
                    rule: htmlExtractor.firstRule(source.ruleToc, keys: ["volumeName", "volume"]),
                    fallbackKeys: ["volumeName", "volume", "group"],
                    variables: variables
                ) ?? currentVolume,
                wordCount: jsonExtractor.string(
                    from: item,
                    rule: htmlExtractor.firstRule(source.ruleToc, keys: ["wordCount", "wordNum", "words"]),
                    fallbackKeys: ["wordCount", "wordNum", "words", "word_count"],
                    variables: variables
                )?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                mediaKind: mediaOverride(in: variables, book: book),
            useReplaceRule: (variables["book"] as? LegadoSearchBookBridge)?.useReplaceRuleOverride
            ))
        }

        if chapters.isEmpty, urlRule == nil, let title = singleTitleWithoutURL,
           let chapter = singleMediaChapter(title: title, variables: variables, book: book, response: response) {
            return .success(ChapterListPage(chapters: [chapter], nextTocUrl: nil, trailingVolume: catalog.inheritedVolume))
        }

        let next: String?
        if let htmlRoot {
            let rawNext = try? htmlExtractor.value(from: htmlRoot, rule: nextRule, baseUrl: response.url, variables: variables)
            next = sanitizeNextTocURL(rawNext, currentURL: response.url).map { htmlExtractor.absolutize($0, base: response.url) }
        } else if let dict = rootObject as? [String: Any] {
            let rawNext = jsonExtractor.string(
                from: dict,
                rule: nextRule,
                fallbackKeys: ["nextTocUrl", "nextChapterUrl", "nextUrl", "next"],
                variables: variables
            )
            next = sanitizeNextTocURL(rawNext, currentURL: response.url).map { htmlExtractor.absolutize($0, base: response.url) }
        } else {
            next = nil
        }

        if chapters.isEmpty {
            let jsError = executionContext.currentJavaScriptError
            let shape = htmlRoot == nil ? "JSON " : ""
            let details = htmlRoot == nil ? "；结构 \(Self.jsonShapeHint(response.body))" : ""
            let message = items.isEmpty
                ? (jsError.map { "目录规则 JS 异常：\($0)" }
                    ?? "\(shape)目录规则未命中（0 项，响应 \(response.body.count) 字符\(details)）")
                : "\(shape)目录命中 \(items.count) 项但无可用章节（标题为空 \(evidence.missingTitle)，链接为空 \(evidence.missingLink)，链接被过滤 \(evidence.filteredLink)）"
            return .failure(.empty(message))
        }
        return .success(ChapterListPage(chapters: chapters, nextTocUrl: next, trailingVolume: currentVolume))
    }

    /// Builds one chapter row from a TOC element.  Volume rows are consumed
    /// here: Legado keeps them as `BookChapter(isVolume=true)`, while this app
    /// renders volume headings from `volumeName`, so a volume row only updates
    /// the volume inherited by the chapters that follow it.
    /// Same diagnostic as SearchResultParser: when a JSON chapter list rule
    /// matches nothing, print the response's top-level shape so the rule can be
    /// corrected without a manual re-request.
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

    private func projectChapter(
        from element: Element,
        index: Int,
        book: BookDetail,
        response: SourceResponse,
        variables: [String: Any],
        nameRule: String?,
        urlRule: String?,
        tocRule: SourceRule?,
        isVolumeRule: String?,
        currentVolume: inout String?,
        fallbackToAnchor: Bool = false
    ) -> HTMLChapterRow {
        var variables = variables
        variables["result"] = LegadoElementBridge(element: element, baseURL: response.url.absoluteString)
        let title: String
        let rawURL: String
        if fallbackToAnchor {
            title = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            rawURL = ((try? element.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // A configured rule can select a node whose attribute/text is empty.
            // Treat that exactly like a missing rule and fall back to the
            // element itself, otherwise a TOC with slightly different markup
            // silently drops every chapter.
            var extractedTitle = ((try? htmlExtractor.value(from: element, rule: nameRule, fallback: "a@text", baseUrl: response.url, variables: variables)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if extractedTitle.isEmpty {
                extractedTitle = ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            title = extractedTitle

            var extractedURL = ((try? htmlExtractor.value(from: element, rule: urlRule, fallback: "a@href", baseUrl: response.url, variables: variables)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if extractedURL.isEmpty {
                extractedURL = ((try? element.attr("href")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if extractedURL.isEmpty, (try? element.tagName())?.lowercased() == "option" {
                // Legado also accepts `<select>` catalogues: the row is an
                // `<option value="chapter-url">chapter title</option>`, so the
                // default `a@href` fallback has nothing to read.
                extractedURL = ((try? element.attr("value")) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            rawURL = sanitizeSingleChapterURL(extractedURL) ?? ""
        }

        let volumeRaw = isVolumeRule.flatMap { rule in
            try? htmlExtractor.value(from: element, rule: rule, fallback: nil, baseUrl: response.url, variables: variables)
        }
        if isVolumeValue(volumeRaw) {
            let volumeTitle = title.isEmpty
                ? ((try? element.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                : title
            if !volumeTitle.isEmpty { currentVolume = volumeTitle }
            return .volumeMarker
        }

        guard !title.isEmpty, !rawURL.isEmpty else {
            return .missingFields(isTitleMissing: title.isEmpty, isLinkMissing: rawURL.isEmpty)
        }
        let absURL = htmlExtractor.absolutize(rawURL, base: response.url)
        guard isValidChapter(title: title, url: absURL, page: (response.url, false), bookURL: book.bookUrl) else {
            return .filteredLink
        }
        let metadata = chapterMetadata(from: element, rule: tocRule, variables: variables, baseURL: response.url)
        return .chapter(BookChapter(
            title: title,
            url: absURL,
            bookUrl: book.bookUrl,
            index: index,
            isVip: metadata.isVip,
            isPay: metadata.isPay,
            updateTime: metadata.updateTime,
            volumeName: metadata.volumeName ?? currentVolume,
            wordCount: metadata.wordCount,
            mediaKind: mediaOverride(in: variables, book: book),
            useReplaceRule: (variables["book"] as? LegadoSearchBookBridge)?.useReplaceRuleOverride
        ))
    }

    private func singleMediaChapter(title: String, variables: [String: Any], book: BookDetail, response: SourceResponse) -> BookChapter? {
        guard let source = variables["source"] as? BookSource,
              let bridge = variables["book"] as? LegadoSearchBookBridge,
              (source.userMediaKind ?? bridge.mediaKind ?? book.mediaKind ?? source.sourceKind).isStreamMedia,
              htmlExtractor.firstRule(source.ruleContent, keys: ["content", "bookContent"]) != nil,
              let title = title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty else { return nil }
        return BookChapter(title: title, url: response.url.absoluteString, bookUrl: book.bookUrl, index: 0,
            mediaKind: mediaOverride(in: variables, book: book),
            useReplaceRule: (variables["book"] as? LegadoSearchBookBridge)?.useReplaceRuleOverride)
    }

    private func isValidChapter(title: String, url: String, page: (url: URL, allowsSamePage: Bool), bookURL: String) -> Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedURL.isEmpty else { return false }

        // Filter dummy / non-chapter URLs
        if trimmedURL == "!" || trimmedURL == "#" || trimmedURL.lowercased().hasPrefix("javascript:") {
            return false
        }
        if trimmedURL.hasSuffix("/!") || trimmedURL.hasSuffix("/#") {
            return false
        }
        // Filter dummy navigation button titles
        let dummyTitles: Set<String> = [
            "倒序", "正序", "目录", "展开", "收起", "查看目录", "加入书架",
            "上一页", "下一页", "查看全部", "返回目录", "书架", "书签"
        ]
        if dummyTitles.contains(trimmedTitle) {
            return false
        }
        // An authored one-row JSON catalog can read this same page as its entire chapter.
        if page.allowsSamePage {
            return !["书籍详情", "返回详情", "返回封面", "封面", "返回"].contains(trimmedTitle)
        }
        let pageURL = page.url
        // Check if URL is same as the page itself without chapter path
        if trimmedURL == pageURL.absoluteString || trimmedURL == pageURL.absoluteString + "/" {
            return false
        }
        if SourceInlineEnvelope.isAddress(trimmedURL) {
            // Opaque addresses have no HTTP host/path. Compare the whole envelope.
            return trimmedURL != bookURL
        }
        if let u = URL(string: trimmedURL), let b = URL(string: bookURL) {
            if u.host == pageURL.host && u.path == pageURL.path && u.query == pageURL.query && u.fragment == nil {
                return false
            }
            if u.host == b.host && u.path == b.path && u.query == b.query && u.fragment == nil {
                let dummyDetailTitles: Set<String> = ["书籍详情", "返回详情", "返回封面", "封面", "返回"]
                if b.path.hasSuffix("/") || b.path.isEmpty || b.path == "/" || dummyDetailTitles.contains(trimmedTitle) {
                    return false
                }
            }
        }
        return true
    }

    private func sanitizeSingleChapterURL(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let (urlPart, suffixPart) = SearchURLResolver.splitURLAndDirectiveSuffix(raw)
        let firstLine = urlPart
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let firstLine, !firstLine.isEmpty else { return nil }
        return firstLine + suffixPart
    }

    private func sanitizeNextTocURL(_ raw: String?, currentURL: URL) -> String? {
        guard let raw else { return nil }
        let (urlPart, suffixPart) = SearchURLResolver.splitURLAndDirectiveSuffix(raw)
        let candidates = urlPart
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty
                    && line != "#"
                    && line != "!"
                    && !line.lowercased().hasPrefix("javascript:")
            }
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 {
            return candidates[0] + suffixPart
        }
        let currentAbs = currentURL.absoluteString
        let chosen = candidates.first { candidate in
            let abs = htmlExtractor.absolutize(candidate, base: currentURL)
            return abs != currentAbs && abs != currentAbs + "/"
        } ?? candidates[0]
        return chosen + suffixPart
    }
}

struct ChapterListPage: Equatable, Sendable {
    let chapters: [BookChapter]
    let nextTocUrl: String?
    /// Volume in effect at the end of this page.  Paginated TOCs feed this into
    /// the next page as `inheritedVolume`, so a volume that starts on one page
    /// keeps applying to the chapters on the following pages.
    var trailingVolume: String? = nil

}

private extension ChapterListParser {
    /// Mirrors Legado `String.isTrue()` for `ruleToc.isVolume`.  JSON booleans
    /// arrive as "true"/"false" through `JSONRuleExtractor`; HTML rules arrive
    /// as element text.  Empty text, the literal `null`, and the usual false
    /// words mean "not a volume row"; any other non-empty text is true.
    func isVolumeValue(_ value: String?) -> Bool {
        guard let raw = value else { return false }
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if raw == "null" { return false }
        let lowered = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["false", "no", "not", "0", "0.0"].contains(lowered)
    }

    /// Legado boolean fields are frequently exposed as `true` / `"true"` /
    /// `"1"` / `"yes"` or their negations. `nil` means the source did not
    /// provide the field at all, which is different from an explicit `false`
    /// (e.g. `isPay` unknown vs. not purchased).
    func optionalBooleanFlag(_ raw: String?) -> Bool? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else { return nil }
        return !["false", "0", "no", "not", "free", "免费"].contains(value)
    }

    func chapterMetadata(
        from element: Element,
        rule: SourceRule?,
        variables: [String: Any],
        baseURL: URL
    ) -> (isVip: Bool, isPay: Bool?, updateTime: String?, volumeName: String?, wordCount: String?) {
        func extract(_ keys: [String]) -> String? {
            guard let rule, let ruleValue = htmlExtractor.firstRule(rule, keys: keys) else { return nil }
            var variables = variables
            variables["result"] = LegadoElementBridge(element: element, baseURL: baseURL.absoluteString)
            if let value = try? htmlExtractor.value(from: element, rule: ruleValue, fallback: nil, baseUrl: baseURL, variables: variables),
               let trimmed = value.nilIfEmpty {
                return trimmed
            }
            guard let parent = element.parent() else { return nil }
            variables["result"] = LegadoElementBridge(element: parent, baseURL: baseURL.absoluteString)
            if let value = try? htmlExtractor.value(from: parent, rule: ruleValue, fallback: nil, baseUrl: baseURL, variables: variables),
               let trimmed = value.nilIfEmpty,
               !trimmed.contains("\n") {
                // A parent-level fallback matches every sibling anchor, which
                // concatenates values from several chapters ("3200字\n4100字").
                // A single chapter's metadata is never a multi-line value, so
                // reject the aggregate instead of assigning it to one row.
                return trimmed
            }
            return nil
        }
        let vipRaw = extract(["isVip", "vip", "vipFlag"])?.lowercased()
        let isVip = vipRaw.map { !["false", "0", "no", "free", "免费"].contains($0) } ?? false
        let isPay = optionalBooleanFlag(extract(["isPay", "paid", "purchased"]))
        return (
            isVip,
            isPay,
            extract(["updateTime", "update", "time"]),
            extract(["volumeName", "volume"]),
            extract(["wordCount", "wordNum", "words", "word_count"])
        )
    }
}
