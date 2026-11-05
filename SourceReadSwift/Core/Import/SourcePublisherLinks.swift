import Foundation
import SwiftSoup

struct SourcePublisherLink: Identifiable, Equatable, Sendable {
    let title: String
    let url: URL
    let isPageReference: Bool
    var id: String { url.absoluteString }
}

struct SourcePublisherPage: Equatable, Sendable {
    let url: URL
    let links: [SourcePublisherLink]
}

/// Extracts visible import links and literal GET references without executing page scripts.
enum SourcePublisherLinks {
    static func discover(in text: String, at pageURL: URL) -> SourcePublisherPage? {
        var links: [SourcePublisherLink] = []
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
            links = catalogLinks(trimmed, pageURL: pageURL)
        } else if let document = try? SwiftSoup.parse(text, pageURL.absoluteString) {
            for element in (try? document.select("a[href]").array()) ?? [] {
                let raw = (try? element.attr("href")) ?? ""
                let title = (try? element.text()) ?? ""
                let isDownload = element.hasAttr("download") || title.contains("书源") || title.contains("导入")
                if let link = makeLink(raw, title: title, pageURL: pageURL, isReference: false),
                   isDownload || ["json", "xbs"].contains(link.url.pathExtension.lowercased()) || raw.contains("://import") {
                    links.append(link)
                }
            }
            // Only literal fetch(url) calls are offered. Options, dynamic expressions and
            // cross-origin script references are not requests the importer can review safely.
            let pattern = #"\bfetch\s*\(\s*['"]([^'"\r\n]+)['"]\s*\)"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                for script in (try? document.select("script").array()) ?? [] {
                    let body = (try? script.html()) ?? ""
                    for match in regex.matches(in: body, range: NSRange(body.startIndex..., in: body)) {
                        guard let range = Range(match.range(at: 1), in: body),
                              let link = makeLink(String(body[range]), title: "页面引用的数据地址", pageURL: pageURL, isReference: true),
                              link.url.host == pageURL.host, link.url.scheme == pageURL.scheme else { continue }
                        links.append(link)
                    }
                }
            }
        }
        var seen = Set<String>()
        let unique = links.filter { $0.url != pageURL && seen.insert($0.id).inserted }.prefix(200)
        return unique.isEmpty ? nil : SourcePublisherPage(url: pageURL, links: Array(unique))
    }

    private static func catalogLinks(_ text: String, pageURL: URL) -> [SourcePublisherLink] {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return [] }
        let rows: [[String: Any]]
        if let array = object as? [[String: Any]] { rows = array }
        else if let wrapper = object as? [String: Any],
                let array = (wrapper["sources"] ?? wrapper["items"] ?? wrapper["data"]) as? [[String: Any]] { rows = array }
        else { return [] }
        guard !rows.isEmpty, rows.allSatisfy({ row in
            !row.keys.contains { key in
                let lower = key.lowercased()
                return lower == "booksourcename" || lower == "sourcename" || lower == "sourceurl"
                    || lower.hasPrefix("rule") || lower.contains("searchurl") || lower == "search" || lower == "toc"
            }
        }) else { return [] }
        return rows.prefix(200).compactMap { row in
            guard let address = (row["importUrl"] ?? row["importURL"] ?? row["download_url"] ?? row["url"]) as? String else { return nil }
            return makeLink(address, title: (row["name"] ?? row["title"]) as? String ?? "书源链接", pageURL: pageURL, isReference: false)
        }
    }

    private static func makeLink(_ raw: String, title: String, pageURL: URL, isReference: Bool) -> SourcePublisherLink? {
        guard raw.count <= 8_192 else { return nil }
        let parsed = SourceImportLinkParser.parse(raw)
        let address = parsed.kind == .url ? parsed.value : raw
        guard let absolute = URL(string: address, relativeTo: pageURL)?.absoluteURL,
              let url = SourceImportURLNormalizer.url(from: absolute.absoluteString),
              url.user == nil, url.password == nil else { return nil }
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return SourcePublisherLink(title: String((label.isEmpty ? url.lastPathComponent : label).prefix(120)),
            url: url, isPageReference: isReference)
    }
}
