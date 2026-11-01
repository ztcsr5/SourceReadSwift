import Foundation

/// Preserve lazy originals and Legado per-image URL options before HTML is
/// stripped. A greedy `.*src` regex picked transparent placeholders instead.
enum ContentImageNormalizer {
    private static let tags = try! NSRegularExpression(pattern: #"<(?:img|amp-img|image)\b[\s\S]*?>"#, options: .caseInsensitive)
    private static let attributes = ["data-original", "data-src", "data-lazy-src", "data-url", "data-lazy", "src", "xlink:href", "href"].map { key in
        try! NSRegularExpression(pattern: #"(?:\s)"# + NSRegularExpression.escapedPattern(for: key) + #"\s*=\s*(?:(["'])([\s\S]*?)\1(?=\s|/?>)|([^\s>"']+))"#, options: .caseInsensitive)
    }
    static func tokens(in text: String) -> String {
        let ns = text as NSString
        var output = text
        for match in tags.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let tag = ns.substring(with: match.range)
            let candidate = imageURL(in: tag)
            guard let range = Range(match.range, in: output) else { continue }
            output.replaceSubrange(range, with: candidate.map { "\n[img]\($0)[/img]\n" } ?? "")
        }
        return output
    }

    static func imageURL(in tag: String) -> String? {
        // Some source JS emits literal \" delimiters, not just JSON escaping
        // in the source definition. Restrict unescaping to the image tag.
        let tag = tag.replacingOccurrences(of: #"\""#, with: "\"")
        for re in attributes {
            // The closing quote must precede the next attribute / tag end.
            // Some Legado rules put unescaped JSON quotes inside src options.
            guard let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { continue }
            let range = m.range(at: m.range(at: 2).location == NSNotFound ? 3 : 2)
            let raw = (tag as NSString).substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = raw.lowercased()
            guard !raw.isEmpty, raw != "#", !lower.hasPrefix("javascript:"),
                  !lower.hasPrefix("data:image/gif") else { continue }
            return raw
        }
        return nil
    }
}

struct ComicImageRequest: Equatable, Sendable {
    let url: String
    let headers: [String: String]

    static func resolve(object: [String: Any], base: String) -> ComicImageRequest? {
        guard let raw = (object["url"] ?? object["src"] ?? object["image"]) as? String,
              let request = resolve(raw, base: base) else { return nil }
        let value = object["headers"] ?? object["header"]
        let explicit: [String: String]
        if let dictionary = value as? [String: String] {
            explicit = dictionary
        } else if let text = value as? String, let data = text.data(using: .utf8),
                  let dictionary = try? JSONDecoder().decode([String: String].self, from: data) {
            explicit = dictionary
        } else { explicit = [:] }
        // Object options override URL directives, case-insensitively. Keep
        // source/chapter fallback separate until the actual request is made.
        var headers = request.headers
        for (key, value) in explicit {
            for existing in Array(headers.keys) where existing.caseInsensitiveCompare(key) == .orderedSame {
                headers.removeValue(forKey: existing)
            }
            headers[key] = value
        }
        return .init(url: request.url, headers: headers)
    }

    static func resolve(_ raw: String, base: String) -> ComicImageRequest? {
        let decoded = ResponseFormatDetector.decodeHTMLEntities(raw)
        if let url = URL(string: decoded), InlineImageStore.isInlineURL(url) {
            return .init(url: decoded, headers: [:])
        }
        let option = SourceURLDirectiveParser().parse(decoded)
        guard let url = MediaURLResolver.resolve(option.urlText, base: base) else { return nil }
        return .init(url: url, headers: option.headers)
    }

    func mergingHeaders(_ sourceHeaders: [String: String], chapterURL: String) -> [String: String] {
        var result = sourceHeaders
        // Chapter-level Referer, not the source's homepage, is the correct
        // default for hotlink protection. Explicit image options win last.
        if !result.keys.contains(where: { $0.caseInsensitiveCompare("Referer") == .orderedSame }) {
            result["Referer"] = chapterURL
        }
        for (key, value) in headers {
            for existing in Array(result.keys) where existing.caseInsensitiveCompare(key) == .orderedSame {
                result.removeValue(forKey: existing)
            }
            result[key] = value
        }
        return result
    }
}
