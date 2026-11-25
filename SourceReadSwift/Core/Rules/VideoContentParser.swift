import Foundation
import SwiftSoup

enum VideoContentParser {
    private static let directKeys = [
        "playUrl", "play_url", "videoUrl", "video_url", "streamUrl",
        "cdnUrl", "ossUrl", "vurl", "play_addr", "main_url", "backup_url",
        "realUrl", "rawUrl", "contentUrl", "hls", "mp4", "m3u8", "video", "src"
    ]
    private static let containerKeys = [
        "sources", "streams", "playlist", "urls", "video_list", "video_model",
        "data", "result", "info", "playInfo", "media", "episode", "list", "items"
    ]
    private static let binaryExtensions: Set<String> = ["mp4", "flv", "mov", "m4v", "webm", "mkv"]
    private static let videoExtensions: Set<String> = ["m3u8", "mp4", "flv", "mov", "m4v", "mpd", "webm", "mkv"]
    private static let embeddedQueryKeys: Set<String> = ["url", "vurl", "src", "playurl", "video"]
    private static let macCMSPlayerPattern = try! NSRegularExpression(
        pattern: #"\bplayer_(?:aaaa|data)\s*=\s*"#, options: .caseInsensitive
    )

    /// Direct stream URLs should be handed to AVPlayer, not downloaded as chapter HTML.
    static func directPlaybackURL(_ rule: String, base: String) -> String? {
        let (urlPart, suffix) = SearchURLResolver.splitURLAndDirectiveSuffix(rule)
        guard let resolved = MediaURLResolver.resolve(urlPart, base: base), isVideo(resolved) else { return nil }
        return resolved + suffix
    }

    /// True when the URL points to a binary video container rather than an HLS/DASH text manifest.
    static func isBinaryVideoStream(_ raw: String) -> Bool {
        let urlPart = SearchURLResolver.splitURLAndDirectiveSuffix(raw).0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: urlPart) else { return false }
        if binaryExtensions.contains(parsed.pathExtension.lowercased()) { return true }
        return parsed.query?.lowercased().contains("mime_type=video") == true
    }

    /// True when `ruleContent` is absent, empty, or simply echoes `baseUrl` without inspecting response body.
    static func isDirectBaseURLContentRule(_ rule: SourceRule?) -> Bool {
        let candidate = rule?.fields["content"]?.nilIfEmpty ?? rule?.fields["bookContent"]?.nilIfEmpty ?? rule?.raw
        let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return true }
        var unwrapped = raw
        if unwrapped.lowercased().hasPrefix("@js:") {
            unwrapped = String(unwrapped.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if unwrapped.lowercased().hasPrefix("<js>"), unwrapped.lowercased().hasSuffix("</js>") {
            unwrapped = String(unwrapped.dropFirst(4).dropLast(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if unwrapped == "{{baseUrl}}" {
            return true
        }
        while unwrapped.hasSuffix(";") {
            unwrapped.removeLast()
            unwrapped = unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return unwrapped == "baseUrl" || unwrapped == "result=baseUrl" || unwrapped == "result = baseUrl"
    }

    static func parseVideoURL(from content: ChapterContent, chapterURL: String? = nil) -> String? {
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = chapterURL ?? content.chapter.url
        let (address, directive) = SearchURLResolver.splitURLAndDirectiveSuffix(text)
        if !directive.isEmpty, !address.contains(where: { $0.isWhitespace }),
           let resolved = MediaURLResolver.resolvePlaybackReference(text, base: base) { return resolved }
        let normalized = text
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\u002[fF]"#, with: "/", options: .regularExpression)

        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let resolved = extractFromJSON(json, base: base, depth: 6) {
            return resolved
        }

        if let macCMSResolved = extractMacCMSPlayerURL(from: text, base: base) {
            return macCMSResolved
        }

        if normalized.contains("<"), let doc = try? SwiftSoup.parse(normalized) {
            for selector in ["video[src], video source[src]", "video[data-src], video source[data-src], video source[data-url]",
                             "source[type^='video/'][data-url]"] {
                if let media = try? doc.select(selector) {
                    for element in media.array() {
                        let raw = ((try? element.attr("src")).flatMap { $0.isEmpty ? nil : $0 })
                            ?? ((try? element.attr("data-src")).flatMap { $0.isEmpty ? nil : $0 })
                            ?? (try? element.attr("data-url"))
                        if let raw, let url = MediaURLResolver.resolvePlaybackReference(raw, base: base) {
                            return url
                        }
                    }
                }
            }
            if let frames = try? doc.select("iframe[src], iframe[data-src], embed[src]") {
                for frame in frames.array() {
                    let raw = ((try? frame.attr("src")).flatMap { $0.isEmpty ? nil : $0 })
                        ?? ((try? frame.attr("data-src")).flatMap { $0.isEmpty ? nil : $0 })
                    guard let raw else { continue }
                    if let embedded = extractEmbeddedStreamURL(from: raw, base: base) {
                        return embedded
                    }
                    if isVideo(raw), let resolved = MediaURLResolver.resolvePlaybackReference(raw, base: base) {
                        return resolved
                    }
                }
            }
        }

        // Do not cut at .m3u8/.mp4: signed streams require their query tokens.
        if let regex = try? NSRegularExpression(pattern: #"https?://[^\s<>"'`\\]+"#, options: .caseInsensitive) {
            let ns = normalized as NSString
            for match in regex.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) {
                let candidate = ns.substring(with: match.range).replacingOccurrences(of: "&amp;", with: "&")
                if let embedded = extractEmbeddedStreamURL(from: candidate, base: base) { return embedded }
                if isVideo(candidate), let url = MediaURLResolver.resolvePlaybackReference(candidate, base: base) { return url }
            }
        }

        if !text.contains(where: { $0.isWhitespace }), !text.contains("<"),
           text.hasPrefix("http") || text.hasPrefix("//") || isVideo(text),
           let url = MediaURLResolver.resolvePlaybackReference(text, base: base) {
            return extractEmbeddedStreamURL(from: url, base: base) ?? url
        }
        if isVideo(base) { return MediaURLResolver.resolvePlaybackReference(base, base: base) }
        return nil
    }

    private static func extractEmbeddedStreamURL(from raw: String, base: String) -> String? {
        let urlPart = SearchURLResolver.splitURLAndDirectiveSuffix(raw).0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isVideo(urlPart) else { return nil }
        let fullURL = MediaURLResolver.resolve(urlPart, base: base) ?? urlPart
        guard let components = URLComponents(string: fullURL), let items = components.queryItems else { return nil }
        for item in items where embeddedQueryKeys.contains(item.name.lowercased()) {
            guard let inner = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !inner.isEmpty else { continue }
            let unescapedInner = inner.replacingOccurrences(of: #"\/"#, with: "/")
            if isVideo(unescapedInner), let resolved = MediaURLResolver.resolvePlaybackReference(unescapedInner, base: base) {
                return resolved
            }
        }
        return nil
    }

    private static func extractMacCMSPlayerURL(from text: String, base: String) -> String? {
        let ns = text as NSString
        let matches = macCMSPlayerPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard let afterEquals = Range(match.range, in: text)?.upperBound,
                  let jsonSlice = balancedJSONObject(in: text, from: afterEquals),
                  let data = jsonSlice.data(using: .utf8),
                  let object = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) as? [String: Any],
                  let rawURL = (object["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawURL.isEmpty else { continue }
            let encryptMode: Int = {
                if let num = object["encrypt"] as? Int { return num }
                if let num = object["encrypt"] as? NSNumber { return num.intValue }
                if let str = object["encrypt"] as? String, let parsed = Int(str.trimmingCharacters(in: .whitespacesAndNewlines)) { return parsed }
                return 0
            }()
            let decodedURL = decodeMacCMSURL(rawURL, encryptMode: encryptMode)
                .replacingOccurrences(of: #"\/"#, with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !decodedURL.isEmpty else { continue }
            if let embedded = extractEmbeddedStreamURL(from: decodedURL, base: base) { return embedded }
            if looksLikeMediaReference(decodedURL),
               let resolved = MediaURLResolver.resolvePlaybackReference(decodedURL, base: base) {
                return resolved
            }
        }
        return nil
    }

    private static func decodeMacCMSURL(_ raw: String, encryptMode: Int) -> String {
        var current = raw
        if encryptMode == 2 {
            let compact = current.filter { !$0.isWhitespace }
            if let decodedData = Data(base64Encoded: compact),
               let decodedText = String(data: decodedData, encoding: .utf8), !decodedText.isEmpty {
                current = decodedText
            }
        }
        if encryptMode == 1 || encryptMode == 2 {
            // Stop percent-decoding as soon as a transport prefix appears so signed query tokens (%2B) stay intact.
            for _ in 0..<3 {
                if current.hasPrefix("http://") || current.hasPrefix("https://") || current.hasPrefix("//") || current.hasPrefix("/") {
                    break
                }
                guard let next = current.removingPercentEncoding, next != current else { break }
                current = next
            }
        }
        return current
    }

    private static func balancedJSONObject(in text: String, from start: String.Index) -> String? {
        var cursor = start
        while cursor < text.endIndex, text[cursor].isWhitespace {
            cursor = text.index(after: cursor)
        }
        guard cursor < text.endIndex, text[cursor] == "{" else { return nil }
        let objectStart = cursor
        var depth = 0
        var quote: Character?
        var escaped = false
        while cursor < text.endIndex {
            let ch = text[cursor]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == activeQuote {
                    quote = nil
                }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[objectStart...cursor])
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func extractFromJSON(_ value: Any, base: String, depth: Int) -> String? {
        guard depth > 0 else { return nil }
        if let raw = value as? String {
            let unescaped = raw.replacingOccurrences(of: #"\/"#, with: "/").trimmingCharacters(in: .whitespacesAndNewlines)
            if let embedded = extractEmbeddedStreamURL(from: unescaped, base: base) { return embedded }
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
        guard !mime.hasPrefix("audio/"), !mime.hasPrefix("image/") else { return nil }
        for key in directKeys {
            if let raw = object[key] as? String {
                let unescaped = raw.replacingOccurrences(of: #"\/"#, with: "/")
                if let embedded = extractEmbeddedStreamURL(from: unescaped, base: base) { return embedded }
                if let url = MediaURLResolver.resolvePlaybackReference(unescaped, base: base) { return url }
            }
        }
        for key in containerKeys {
            if let nested = object[key], let resolved = extractFromJSON(nested, base: base, depth: depth - 1) {
                return resolved
            }
        }
        guard let fallback = object["url"] as? String else { return nil }
        let unescapedFallback = fallback.replacingOccurrences(of: #"\/"#, with: "/")
        return extractEmbeddedStreamURL(from: unescapedFallback, base: base)
            ?? MediaURLResolver.resolvePlaybackReference(unescapedFallback, base: base)
    }

    private static func looksLikeMediaReference(_ raw: String) -> Bool {
        raw.hasPrefix("http://") || raw.hasPrefix("https://") || raw.hasPrefix("//")
            || raw.hasPrefix("/") || raw.hasPrefix("./") || raw.hasPrefix("../") || isVideo(raw)
    }

    static func isVideo(_ raw: String) -> Bool {
        let urlPart = SearchURLResolver.splitURLAndDirectiveSuffix(raw).0.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: urlPart) else { return false }
        if videoExtensions.contains(parsed.pathExtension.lowercased()) { return true }
        return parsed.query?.lowercased().contains("mime_type=video") == true
    }
}
