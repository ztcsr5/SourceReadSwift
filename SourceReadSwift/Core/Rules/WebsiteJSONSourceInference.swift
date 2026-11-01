import Foundation

/// Infer only fields observed in two direct JSON responses; never guess API URLs.
enum WebsiteJSONSourceInference {
    private struct CatalogFields {
        let path: String
        let name: String
        let url: String
    }

    private static let catalogPaths = ["$.chapters[*]", "$.catalog[*]", "$.list[*]", "$.items[*]",
        "$.data.chapters[*]", "$.data.catalog[*]", "$.data.list[*]", "$.data.items[*]",
        "$.result.chapters[*]", "$.result.list[*]", "$[*]"]
    private static let contentPaths = ["$.content", "$.text", "$.body", "$.chapterContent",
        "$.data.content", "$.data.text", "$.data.body", "$.data.chapterContent",
        "$.result.content", "$.result.text"]

    static func infer(catalog: WebsitePageSample, chapter: WebsitePageSample,
                      name: String, selectors: (toc: String, content: String)) throws -> WebsiteSourceDraft {
        guard let catalogObject = ResponseFormatDetector.jsonObject(from: catalog.html),
              let chapterObject = ResponseFormatDetector.jsonObject(from: chapter.html),
              let base = WebsiteSourceInference.origin(catalog.url) else { throw WebsiteSourceInference.Failure.invalidSample }
        let extractor = JSONRuleExtractor()
        // Manual edits remain restricted to the supported JSONPath grammar,
        // not arbitrary JavaScript hidden in a selector field.
        let tocPaths = try selectedPaths(selectors.toc, candidates: catalogPaths)
        let bodyPaths = try selectedPaths(selectors.content, candidates: contentPaths)
        let fields = tocPaths.compactMap { path -> CatalogFields? in
            guard let rows = extractor.value(from: catalogObject, path: path) as? [[String: Any]] else { return nil }
            return inferCatalogFields(rows, path: path)
        }
        guard fields.count == 1, let toc = fields.first else { throw WebsiteSourceInference.Failure.noCatalog }
        let matchingContent = bodyPaths.filter {
            guard let text = extractor.value(from: chapterObject, path: $0) as? String else { return false }
            return text.trimmingCharacters(in: .whitespacesAndNewlines).count >= 80
        }
        guard matchingContent.count == 1, let contentPath = matchingContent.first else { throw WebsiteSourceInference.Failure.noContent }
        let title = ["$.bookName", "$.title", "$.data.bookName", "$.data.title"].compactMap {
            (extractor.value(from: catalogObject, path: $0) as? String)?.nilIfEmpty
        }.first ?? "接口书籍"
        let sourceName = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (catalog.url.host ?? "接口书源")
        let source = BookSource(bookSourceName: sourceName,
            bookSourceUrl: base + "#local-inference-" + UUID().uuidString,
            bookSourceGroup: "网页本地解析",
            ruleBookInfo: .init(fields: [:]),
            ruleToc: .init(fields: ["chapterList": toc.path, "chapterName": "$." + toc.name, "chapterUrl": "$." + toc.url]),
            ruleContent: .init(fields: ["content": contentPath]), loginUrl: base,
            raw: ["sourceComment": "本地直接 JSON 样本生成，只验证已提供的目录/正文接口。未推断搜索、发现、分页、签名或加密接口。"])
        let book = SearchBook(name: title, author: nil, coverUrl: nil, bookUrl: catalog.url.absoluteString,
                              sourceName: sourceName, sourceUrl: source.bookSourceUrl, intro: nil)
        let detail = try BookDetailParser().parse(source: source, book: book, response: WebsiteSourceInference.response(catalog)).get()
        let chapters = try ChapterListParser().parse(source: source, book: detail, response: WebsiteSourceInference.response(catalog)).get()
        guard chapters.count >= 2, chapters.count <= 10_000,
              chapters.allSatisfy({
                  guard let url = WebsiteSourceInference.validURL($0.url) else { return false }
                  return WebsiteSourceInference.origin(url) == base
              }),
              let selected = chapters.first(where: { $0.url == chapter.url.absoluteString }) else { throw WebsiteSourceInference.Failure.invalidSample }
        let body = try ContentParser().parse(source: source, chapter: selected, response: WebsiteSourceInference.response(chapter)).get()
        guard body.paragraphs.joined().count >= 80 else { throw WebsiteSourceInference.Failure.noContent }
        return WebsiteSourceDraft(source: source, example: book, chapterCount: chapters.count,
                                  preview: Array(body.paragraphs.prefix(4)), tocSelector: toc.path, contentSelector: contentPath)
    }

    private static func selectedPaths(_ requested: String, candidates: [String]) throws -> [String] {
        let path = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return candidates }
        guard candidates.contains(path) else { throw WebsiteSourceInference.Failure.invalidSample }
        return [path]
    }

    private static func inferCatalogFields(_ rows: [[String: Any]], path: String) -> CatalogFields? {
        guard rows.count >= 2, rows.count <= 10_000 else { return nil }
        let name = ["chapterName", "title", "name"].first { key in
            rows.allSatisfy { ($0[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        }
        let url = ["chapterUrl", "url", "href"].first { key in
            rows.allSatisfy { row in
                guard let text = row[key] as? String else { return false }
                return WebsiteSourceInference.validURL(text) != nil
            }
        }
        guard let name, let url else { return nil }
        return CatalogFields(path: path, name: name, url: url)
    }
}
