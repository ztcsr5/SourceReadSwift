import Foundation
import SwiftSoup

struct SmartWebArticle: Equatable, Sendable {
    let title: String
    let paragraphs: [String]

    var text: String { paragraphs.joined(separator: "\n\n") }
}

/// Turns an arbitrary article page into a readable, native-text projection.
/// This is intentionally conservative: scripts, navigation and repeated
/// boilerplate are removed, while short paragraphs are retained in order.
enum SmartWebArticleExtractor {
    static func extract(html: String, fallbackTitle: String = "网页文章") -> SmartWebArticle {
        guard let document = try? SwiftSoup.parse(html) else {
            return SmartWebArticle(title: fallbackTitle, paragraphs: plainText(html))
        }
        for selector in ["script", "style", "noscript", "nav", "header", "footer", "form", "aside", "[hidden]", "[aria-hidden=true]", "ins.adsbygoogle"] {
            try? document.select(selector).remove()
        }
        let title = (try? document.title())?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? fallbackTitle
        let candidates: [SwiftSoup.Element] = (try? Array(document.select("article, main, #content, #chaptercontent, .read-content, [class*=content], [class*=article], body"))) ?? []
        let root = candidates.max { score($0) < score($1) } ?? ((try? document.body()) ?? nil)
        let paragraphs = root.map { plainText(blockText($0)) } ?? []
        return SmartWebArticle(title: title, paragraphs: paragraphs)
    }

    private static func plainText(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: "  ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func score(_ element: SwiftSoup.Element) -> Double {
        let text = (try? element.text()) ?? ""
        let links = (try? element.select("a").text()) ?? ""
        let weight: Double = ["article", "main"].contains(element.tagName()) ? 1.5 : (element.tagName() == "body" ? 0.65 : 1)
        return Double(max(text.count - links.count * 3, 0)) * weight
    }

    private static func blockText(_ node: SwiftSoup.Node) -> String {
        if let text = node as? SwiftSoup.TextNode { return text.getWholeText() }
        let tag = (node as? SwiftSoup.Element)?.tagName() ?? ""
        if tag == "br" { return "\n" }
        let block = ["p", "div", "section", "article", "main", "h1", "h2", "h3", "li", "blockquote"].contains(tag)
        let children = node.getChildNodes().map(blockText).joined()
        return block ? "\n" + children + "\n" : children
    }
}
