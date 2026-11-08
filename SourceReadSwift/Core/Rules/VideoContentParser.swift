import Foundation
import SwiftSoup

enum VideoContentParser {
    static func parseVideoURL(from content: ChapterContent, chapterURL: String? = nil) -> String? {
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = chapterURL ?? content.chapter.url
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["url", "playUrl", "video"] {
                if let raw = json[key] as? String,
                   let url = MediaURLResolver.resolve(raw, base: base) { return url }
            }
        }
        if text.contains("<"), let doc = try? SwiftSoup.parse(text),
           let media = try? doc.select("video[src], video source[src]") {
            for element in media.array() {
                if let raw = try? element.attr("src"), let url = MediaURLResolver.resolve(raw, base: base) { return url }
            }
        }
        // Do not cut at .m3u8/.mp4: signed streams require their query tokens.
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#, options: .caseInsensitive) {
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
