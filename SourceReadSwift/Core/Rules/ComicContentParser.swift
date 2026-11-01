import Foundation
import SwiftSoup

struct ComicPage: Identifiable, Hashable, Sendable {
    let id: Int
    let url: String
    var headers: [String: String] = [:]
}

enum ComicContentParser {
    static func parsePages(from content: ChapterContent) -> [ComicPage] {
        let base = content.chapter.url
        var requests: [ComicImageRequest] = []
        for paragraph in content.paragraphs {
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            var candidates: [String] = []
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                if let list = json as? [String] { candidates = list }
                else if let list = json as? [[String: Any]] {
                    // Retain per-page hotlink headers. Flattening an object
                    // to its URL made an otherwise valid API return 403 images.
                    for object in list {
                        guard let request = ComicImageRequest.resolve(object: object, base: base), requests.last != request else { continue }
                        requests.append(request)
                    }
                    continue
                }
            }
            let imageText = ContentImageNormalizer.tokens(in: text)
            if candidates.isEmpty {
                for pattern in [#"\[img\]([\s\S]*?)\[/img\]"#, #"!\[[^\]]*\]\(([^\s\)]+)\)"#] {
                    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                    let ns = imageText as NSString
                    candidates += regex.matches(in: imageText, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
                }
            }
            if candidates.isEmpty, !text.contains(where: { $0.isWhitespace }),
               !text.contains("<"), !text.contains("[") {
                let ext = URL(string: text)?.pathExtension.lowercased() ?? ""
                if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("//")
                    || ["jpg", "jpeg", "png", "webp", "gif", "avif"].contains(ext) { candidates = [text] }
            }
            for candidate in candidates {
                guard let request = ComicImageRequest.resolve(candidate, base: base), requests.last != request else { continue }
                requests.append(request)
            }
        }
        return requests.enumerated().map { ComicPage(id: $0.offset, url: $0.element.url, headers: $0.element.headers) }
    }
}
