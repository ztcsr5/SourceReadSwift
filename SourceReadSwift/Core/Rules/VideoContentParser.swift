import Foundation
import SwiftSoup

enum VideoContentParser {
    private static let directKeys = ["url", "playUrl", "play_url", "videoUrl", "video_url", "video", "streamUrl", "hls", "mp4", "m3u8", "src"]
    private static let containerKeys = ["data", "result", "info", "playInfo", "media", "episode"]

    static func parseVideoURL(from content: ChapterContent, chapterURL: String? = nil) -> String? {
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = chapterURL ?? content.chapter.url
        let normalized = text.replacingOccurrences(of: #"\/"#, with: "/")

        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let resolved = extractFromJSON(json, base: base, depth: 5) {
            return resolved
        }

        if normalized.contains("<"), let doc = try? SwiftSoup.parse(normalized) {
            for selector in ["video[src], video source[src]", "video[data-src], video source[data-src], source[data-url]"] {
                if let media = try? doc.select(selector) {
                    for element in media.array() {
                        let raw = ((try? element.attr("src")).flatMap { $0.isEmpty ? nil : $0 })
                            ?? ((try? element.attr("data-src")).flatMap { $0.isEmpty ? nil : $0 })
                            ?? (try? element.attr("data-url"))
                        if let raw, let url = MediaURLResolver.resolve(raw, base: base) {
                            return url
                        }
                    }
                }
            }
        }

        // Do not cut at .m3u8/.mp4: signed streams require their query tokens.
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'`\\]+"#, options: .caseInsensitive) {
            let ns = normalized as NSString
            for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
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

    private static func extractFromJSON(_ value: Any, base: String, depth: Int) -> String? {
        guard depth > 0 else { return nil }
        if let raw = value as? String {
            let unescaped = raw.replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksLikeMediaReference(unescaped) else { return nil }
            return MediaURLResolver.resolve(unescaped, base: base)
        }
        if let array = value as? [Any] {
            for item in array {
                if let resolved = extractFromJSON(item, base: base, depth: depth - 1) { return resolved }
            }
            return nil
        }
        guard let object = value as? [String: Any] else { return nil }
        for key in directKeys {
            if let raw = object[key] as? String {
                let unescaped = raw.replacingOccurrences(of: #"\/"#, with: "/")
                if let url = MediaURLResolver.resolve(unescaped, base: base) { return url }
            }
        }
        for key in containerKeys {
            if let nested = object[key], let resolved = extractFromJSON(nested, base: base, depth: depth - 1) {
                return resolved
            }
        }
        return nil
    }

    private static func looksLikeMediaReference(_ raw: String) -> Bool {
        raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("//")
            || raw.hasPrefix("/") || raw.hasPrefix("./") || raw.hasPrefix("../") || isVideo(raw)
    }

    private static func isVideo(_ raw: String) -> Bool {
        ["m3u8", "mp4", "flv", "mov", "m4v", "mpd", "webm"].contains(URL(string: raw)?.pathExtension.lowercased() ?? "")
    }
}
