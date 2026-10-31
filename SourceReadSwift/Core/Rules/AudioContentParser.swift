import Foundation
import SwiftSoup

enum AudioContentParser {
    static func parseURL(_ text: String, base: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = (json["url"] ?? json["playUrl"] ?? json["audioUrl"] ?? json["audio"]) as? String,
           let url = MediaURLResolver.resolve(raw, base: base) { return url }
        if text.contains("<"), let doc = try? SwiftSoup.parse(text),
           let media = try? doc.select("audio[src], source[src]") {
            for element in media.array() {
                if let raw = try? element.attr("src"), let url = MediaURLResolver.resolve(raw, base: base) { return url }
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"']+"#, options: .caseInsensitive) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: match.range)
                if isMediaURL(raw), let url = MediaURLResolver.resolve(raw, base: base) { return url }
            }
        }
        guard !text.contains(where: { $0.isWhitespace }), !text.contains("<"),
              text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("//") || isMediaURL(text)
        else { return nil }
        return MediaURLResolver.resolve(text, base: base)
    }

    static func isMediaURL(_ raw: String) -> Bool {
        ["mp3", "m4a", "aac", "ogg", "wav", "flac", "m3u8"].contains(URL(string: raw)?.pathExtension.lowercased() ?? "")
    }
}
