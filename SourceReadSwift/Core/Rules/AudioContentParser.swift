import Foundation
import SwiftSoup

enum AudioContentParser {
    private static let directKeys = ["url", "playUrl", "play_url", "audioUrl", "audio_url", "audio", "streamUrl", "src"]
    private static let containerKeys = ["data", "result", "info", "playInfo", "track", "media"]

    static func parseURL(_ text: String, base: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = text.replacingOccurrences(of: #"\/"#, with: "/")
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let resolved = extractFromJSON(json, base: base, depth: 5) {
            return resolved
        }
        if normalized.contains("<"), let doc = try? SwiftSoup.parse(normalized),
           let media = try? doc.select("audio[src], audio[data-src], source[src], source[data-src], audio source[src]") {
            for element in media.array() {
                let raw = ((try? element.attr("src")).flatMap { $0.isEmpty ? nil : $0 })
                    ?? (try? element.attr("data-src"))
                if let raw, let url = MediaURLResolver.resolve(raw, base: base) { return url }
            }
        }
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'`\\]+"#, options: .caseInsensitive) {
            let ns = normalized as NSString
            for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: match.range)
                if isMediaURL(raw), let url = MediaURLResolver.resolve(raw, base: base) { return url }
            }
        }
        guard !text.contains(where: { $0.isWhitespace }), !text.contains("<"),
              text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("//") || isMediaURL(text)
        else { return nil }
        return MediaURLResolver.resolve(text, base: base)
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
            || raw.hasPrefix("/") || raw.hasPrefix("./") || raw.hasPrefix("../") || isMediaURL(raw)
    }

    static func isMediaURL(_ raw: String) -> Bool {
        ["mp3", "m4a", "aac", "ogg", "wav", "flac", "m3u8", "opus"].contains(URL(string: raw)?.pathExtension.lowercased() ?? "")
    }
}
