import Foundation
import SwiftSoup

struct WebsitePageSample: Sendable {
    let url: URL
    let html: String
}

struct WebsiteSourceDraft: Sendable {
    let source: BookSource
    let example: SearchBook
    let chapterCount: Int
    let preview: [String]
    let tocSelector: String
    let contentSelector: String
}

/// A local, evidence-based starter for ordinary HTML novel sites, not a claim
/// that one page reveals a site's private search API or every template.
enum WebsiteSourceInference {
    enum Failure: LocalizedError {
        case invalidURL, differentSite, oversized, noCatalog, noContent, invalidSample
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "仅支持不含账号密码的 HTTP/HTTPS 网页。"
            case .differentSite: return "目录和正文需来自同一站点（协议、域名、端口一致）。"
            case .oversized: return "网页超过 2 MB，请打开具体目录或章节页后重新采样。"
            case .noCatalog: return "没有识别出章节链接容器；请打开完整目录页，或调整目录 CSS 选择器。"
            case .noContent: return "没有识别出正文容器；请打开正文页，或调整正文 CSS 选择器。"
            case .invalidSample: return "生成规则未通过本地目录与正文解析验证。"
            }
        }
    }

    static func validURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        let sensitive = Set(["token", "access_token", "refresh_token", "password", "passwd", "session", "sessionid", "authorization", "api_key"])
        if URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains(where: { sensitive.contains($0.name.lowercased()) }) == true { return nil }
        return url
    }

    static func origin(_ url: URL) -> String? {
        guard validURL(url.absoluteString) != nil,
              var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        c.path = "/"; c.query = nil; c.fragment = nil
        return c.url?.absoluteString
    }

    static func infer(catalog: WebsitePageSample, chapter: WebsitePageSample,
                      name: String, tocCSS: String = "", contentCSS: String = "") throws -> WebsiteSourceDraft {
        guard let base = origin(catalog.url), let chapterBase = origin(chapter.url) else { throw Failure.invalidURL }
        guard base == chapterBase else { throw Failure.differentSite }
        guard catalog.html.utf8.count <= 2_000_000, chapter.html.utf8.count <= 2_000_000 else { throw Failure.oversized }
        let tocDoc = try SwiftSoup.parse(catalog.html, catalog.url.absoluteString)
        let bodyDoc = try SwiftSoup.parse(chapter.html, chapter.url.absoluteString)
        try bodyDoc.select("script,style,nav,header,footer,form,aside,[hidden],ins.adsbygoogle").remove()
        let toc = tocCSS.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = contentCSS.trimmingCharacters(in: .whitespacesAndNewlines)
        let tocSelector: String
        if !toc.isEmpty { tocSelector = toc }
        else {
            let anchors = try tocDoc.select("a[href]").array().prefix(10_000).filter { link in
                let title = (try? link.text()) ?? ""
                return title.range(of: #"第.{1,16}[章节回话卷]|^\s*\d+[.、\s]"#, options: .regularExpression) != nil
            }
            guard anchors.count >= 2 else { throw Failure.noCatalog }
            var candidates: [Element] = []
            for anchor in anchors.prefix(30) {
                var node = anchor.parent()
                for _ in 0..<4 {
                    guard let current = node, !["body", "html"].contains(current.tagName()) else { break }
                    if !candidates.contains(where: { $0 === current }) { candidates.append(current) }
                    node = current.parent()
                }
            }
            let chapterIDs = Set(anchors.map { ObjectIdentifier($0) })
            let scored = candidates.map { node -> (Element, Double) in
                let links = (try? node.select("a[href]").array()) ?? []
                let valid = links.filter { chapterIDs.contains(ObjectIdentifier($0)) }.count
                return (node, Double(valid * valid) / Double(max(links.count, 1)))
            }
            let root = scored.max(by: { $0.1 < $1.1 })?.0
            guard let root else { throw Failure.noCatalog }
            tocSelector = try root.cssSelector()
        }
        let contentSelector: String
        if !content.isEmpty { contentSelector = content }
        else {
            let candidates = try bodyDoc.select("article,main,#content,#chaptercontent,#chapterContent,.read-content,.reading-content,.showtxt,.chapter-content,.entry-content").array()
            func score(_ node: Element) -> Int {
                max(((try? node.text()) ?? "").count - ((try? node.select("a").text()) ?? "").count * 3, 0)
            }
            guard let root = candidates.max(by: { score($0) < score($1) }), score(root) >= 80 else { throw Failure.noContent }
            contentSelector = try root.cssSelector()
        }
        let title = ((try? tocDoc.select("h1").first()?.text()) ?? nil)?.nilIfEmpty ?? "网页书籍"
        let sourceName = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (catalog.url.host ?? "网页书源")
        // No cookies, credentials, page HTML, scripts or inferred search API
        // enter the exported source. The browser cookie jar stays local.
        let explore = SourceRule(fields: ["bookList": "@css:body", "name": "@css:h1@text", "bookUrl": "@js:baseUrl"])
        let source = BookSource(bookSourceName: sourceName,
            bookSourceUrl: base + "#local-inference-" + UUID().uuidString,
            bookSourceGroup: "网页本地解析", exploreUrl: catalog.url.absoluteString,
            ruleBookInfo: .init(fields: ["name": "@css:h1@text", "tocUrl": catalog.url.absoluteString]),
            ruleToc: .init(fields: ["chapterList": "@css:\(tocSelector) a[href]", "chapterName": "text", "chapterUrl": "href"]),
            ruleContent: .init(fields: ["content": "@css:\(contentSelector)@html", "title": "@css:h1@text"]),
            ruleExplore: explore, loginUrl: base,
            raw: ["sourceComment": "本地 HTML 采样生成，仅验证当前目录与章节模板。未推断全站搜索；动态 API、分页、漫画需另行配置。"])
        let book = SearchBook(name: title, author: nil, coverUrl: nil, bookUrl: catalog.url.absoluteString,
                              sourceName: sourceName, sourceUrl: source.bookSourceUrl, intro: nil)
        let detail = BookDetail(name: title, author: nil, coverUrl: nil, bookUrl: book.bookUrl,
                                sourceName: sourceName, sourceUrl: source.bookSourceUrl, intro: nil,
                                latestChapter: nil, wordCount: nil, status: nil, updateTime: nil, kind: nil)
        let chapters = try ChapterListParser().parse(source: source, book: detail, response: response(catalog)).get()
        guard chapters.count >= 2, chapters.allSatisfy({ value in
            guard let url = validURL(value.url) else { return false }
            return origin(url) == base
        }), let selected = chapters.first(where: {
            guard let url = URL(string: $0.url) else { return false }
            return url.path == chapter.url.path && url.query == chapter.url.query
        }) else { throw Failure.invalidSample }
        let body = try ContentParser().parse(source: source, chapter: selected, response: response(chapter)).get()
        guard body.paragraphs.joined().count >= 80 else { throw Failure.noContent }
        return WebsiteSourceDraft(source: source, example: book, chapterCount: chapters.count,
                                  preview: Array(body.paragraphs.prefix(4)), tocSelector: tocSelector, contentSelector: contentSelector)
    }

    private static func response(_ sample: WebsitePageSample) -> SourceResponse {
        SourceResponse(url: sample.url, statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"],
                       body: sample.html, data: Data(sample.html.utf8))
    }
}
