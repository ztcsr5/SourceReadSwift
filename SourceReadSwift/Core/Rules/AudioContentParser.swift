import Foundation
import SwiftSoup

enum AudioContentParser {
    private static let directKeys = ["playUrl", "play_url", "audioUrl", "audio_url", "audio", "streamUrl", "src"]
    private static let containerKeys = ["sources", "streams", "playlist", "data", "result", "info", "playInfo", "track", "media"]

    static func parseURL(_ text: String, base: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let (address, directive) = SearchURLResolver.splitURLAndDirectiveSuffix(text)
        if !directive.isEmpty, !address.contains(where: { $0.isWhitespace }),
           let resolved = MediaURLResolver.resolvePlaybackReference(text, base: base) { return resolved }
        let normalized = text.replacingOccurrences(of: #"\/"#, with: "/")
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let resolved = extractFromJSON(json, base: base, depth: 5) {
            return resolved
        }
        if normalized.contains("<"), let url = parseHTML(normalized, base: base) { return url }
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'`\\]+"#, options: .caseInsensitive) {
            let ns = normalized as NSString
            for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
                let raw = ns.substring(with: match.range)
                if isMediaURL(raw), let url = MediaURLResolver.resolvePlaybackReference(raw, base: base) { return url }
            }
        }
        guard !text.contains(where: { $0.isWhitespace }), !text.contains("<"),
              text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("//") || isMediaURL(text)
        else { return nil }
        return MediaURLResolver.resolvePlaybackReference(text, base: base)
    }

    private static func parseHTML(_ html: String, base: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let audio = "audio[src], audio[data-src], audio source[src], audio source[data-src]"
        for selector in [audio, "source[src], source[data-src]"] {
            guard let candidates = try? doc.select(selector) else { continue }
            for element in candidates.array() {
                if let url = audioAddress(element, authoredAsAudio: selector == audio, base: base) { return url }
            }
        }
        return nil
    }

    private static func audioAddress(_ element: Element, authoredAsAudio: Bool, base: String) -> String? {
        let mime = ((try? element.attr("type")) ?? "").lowercased()
        guard element.parent()?.tagName() != "video", !mime.hasPrefix("video/"),
              let raw = ((try? element.attr("src")).flatMap { $0.nilIfEmpty }) ?? (try? element.attr("data-src")),
              authoredAsAudio || mime.hasPrefix("audio/") || isMediaURL(raw) else { return nil }
        return MediaURLResolver.resolvePlaybackReference(raw, base: base)
    }

    private static func extractFromJSON(_ value: Any, base: String, depth: Int) -> String? {
        guard depth > 0 else { return nil }
        if let raw = value as? String {
            let unescaped = raw.replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
            guard looksLikeMediaReference(unescaped) else { return nil }
            return MediaURLResolver.resolvePlaybackReference(unescaped, base: base)
        }
        if let array = value as? [Any] {
            for item in array {
                if let resolved = extractFromJSON(item, base: base, depth: depth - 1) { return resolved }
            }
            return nil
        }
        guard let object = value as? [String: Any] else { return nil }
        let mime = ((object["type"] as? String) ?? (object["mime"] as? String) ?? "").lowercased()
        guard !mime.hasPrefix("video/"), !mime.hasPrefix("image/") else { return nil }
        for key in directKeys {
            if let raw = object[key] as? String {
                let unescaped = raw.replacingOccurrences(of: #"\/"#, with: "/")
                if let url = MediaURLResolver.resolvePlaybackReference(unescaped, base: base) { return url }
            }
        }
        for key in containerKeys {
            if let nested = object[key], let resolved = extractFromJSON(nested, base: base, depth: depth - 1) {
                return resolved
            }
        }
        guard let fallback = object["url"] as? String else { return nil }
        return MediaURLResolver.resolvePlaybackReference(fallback, base: base)
    }

    private static func looksLikeMediaReference(_ raw: String) -> Bool {
        raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("//")
            || raw.hasPrefix("/") || raw.hasPrefix("./") || raw.hasPrefix("../") || isMediaURL(raw)
    }

    static func isMediaURL(_ raw: String) -> Bool {
        ["mp3", "m4a", "aac", "ogg", "wav", "flac", "m3u8", "opus"].contains(URL(string: SearchURLResolver.splitURLAndDirectiveSuffix(raw).0)?.pathExtension.lowercased() ?? "")
    }
}
