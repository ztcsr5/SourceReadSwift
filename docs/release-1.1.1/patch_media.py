from pathlib import Path
root=Path(__file__).resolve().parents[2]/'SourceReadSwift/Core/Rules'
(root/'ComicContentParser.swift').write_text('''import Foundation
import SwiftSoup

struct ComicPage: Identifiable, Hashable, Sendable {
    let id: Int
    let url: String
}

enum ComicContentParser {
    static func parsePages(from content: ChapterContent) -> [ComicPage] {
        let base = content.chapter.url
        var urls: [String] = []
        for paragraph in content.paragraphs {
            let text = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            var candidates: [String] = []
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                if let list = json as? [String] { candidates = list }
                else if let list = json as? [[String: Any]] {
                    candidates = list.compactMap { ($0["url"] ?? $0["src"] ?? $0["image"]) as? String }
                }
            }
            if candidates.isEmpty, text.lowercased().contains("<img"),
               let doc = try? SwiftSoup.parse(text), let images = try? doc.select("img") {
                for image in images.array() {
                    // Lazy originals outrank placeholders regardless of attribute order.
                    for key in ["data-original", "data-src", "data-url", "data-lazy-src", "src"] {
                        let raw = (try? image.attr(key)) ?? ""
                        if let resolved = MediaURLResolver.resolve(raw, base: base) {
                            candidates.append(resolved); break
                        }
                    }
                }
            }
            if candidates.isEmpty {
                for pattern in [#"\\[img\\]([\\s\\S]*?)\\[/img\\]"#, #"!\\[[^\\]]*\\]\\(([^\\s\\)]+)\\)"#] {
                    guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                    let ns = text as NSString
                    candidates += regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) }
                }
            }
            if candidates.isEmpty, !text.contains(where: { $0.isWhitespace }),
               !text.contains("<"), !text.contains("[") {
                let ext = URL(string: text)?.pathExtension.lowercased() ?? ""
                if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("//")
                    || ["jpg", "jpeg", "png", "webp", "gif", "avif"].contains(ext) { candidates = [text] }
            }
            for candidate in candidates {
                guard let url = MediaURLResolver.resolve(candidate, base: base), urls.last != url else { continue }
                urls.append(url)
            }
        }
        return urls.enumerated().map { ComicPage(id: $0.offset, url: $0.element) }
    }
}
''',encoding='utf8')
(root/'VideoContentParser.swift').write_text('''import Foundation
import SwiftSoup

enum VideoContentParser {
    static func parseVideoURL(from content: ChapterContent, chapterURL: String? = nil) -> String? {
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = chapterURL ?? content.chapter.url
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = (json["url"] ?? json["playUrl"] ?? json["video"]) as? String,
           let url = MediaURLResolver.resolve(raw, base: base) { return url }
        if text.contains("<"), let doc = try? SwiftSoup.parse(text),
           let media = try? doc.select("video[src], source[src]") {
            for element in media.array() {
                if let raw = try? element.attr("src"), let url = MediaURLResolver.resolve(raw, base: base) { return url }
            }
        }
        // Do not cut at .m3u8/.mp4: signed streams require their query tokens.
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\\s<>"']+"#, options: .caseInsensitive) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: match.range)
                if isVideo(raw), let url = MediaURLResolver.resolve(raw, base: base) { return url }
            }
        }
        if !text.contains(where: { $0.isWhitespace }), !text.contains("<"),
           text.hasPrefix("http") || text.hasPrefix("//") || isVideo(text),
           let url = MediaURLResolver.resolve(text, base: base) { return url }
        if isVideo(base) { return MediaURLResolver.resolve(base, base: base) }
        return nil
    }

    private static func isVideo(_ raw: String) -> Bool {
        ["m3u8", "mp4", "flv", "mov", "m4v"].contains(URL(string: raw)?.pathExtension.lowercased() ?? "")
    }
}
''',encoding='utf8')
