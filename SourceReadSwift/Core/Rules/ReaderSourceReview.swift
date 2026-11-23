import Foundation

/// The reader opens a declared web address, never a source-provided tap script.
struct ReaderSourceReview: Codable, Hashable, Sendable {
    let url: URL
    let isChapter: Bool
    let count: String?
    var paragraph: Int

    var label: String { (isChapter ? "章评" : "段评") + (count.map { " · " + $0 } ?? "") }

    static func webURL(_ address: String, base: URL? = nil) -> URL? {
        guard address.utf8.count <= 8192, !address.isEmpty, !address.hasPrefix("#"),
              address.rangeOfCharacter(from: .controlCharacters) == nil,
              let url = URL(string: address, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// Only keep anchors whose original paragraph survives cleanup. Ambiguous repeated text is not reattached by guesswork.
    static func rebase(_ reviews: [Self]?, from original: [String], to revised: [String]) -> [Self]? {
        guard let reviews, !reviews.isEmpty else { return nil }
        if original == revised { return reviews }
        // Keep the nth occurrence only when no identical paragraph was added or removed.
        var occurrences: [String: Int] = [:]
        let ordinals = original.map { line -> Int in
            let ordinal = occurrences[line, default: 0]; occurrences[line] = ordinal + 1; return ordinal
        }
        let indices = Dictionary(grouping: revised.indices, by: { revised[$0] })
        let result = reviews.compactMap { review -> Self? in
            if review.isChapter { return review }
            guard original.indices.contains(review.paragraph) else { return nil }
            let line = original[review.paragraph]
            guard let matches = indices[line], matches.count == occurrences[line] else { return nil }
            var next = review; next.paragraph = matches[ordinals[review.paragraph]]; return next
        }
        return result.isEmpty ? nil : result
    }
}

enum ReaderReviewMarkup {
    private static let tags = try! NSRegularExpression(pattern: #"<(comment|img|a)\b(?:[^>"'<>]++|"[^"]*+"|'[^']*+')*+>(?:[^<>]{0,160}</\1\s*>)?"#, options: .caseInsensitive)
    private static let action = try! NSRegularExpression(pattern: #"(?:\bonPress\s*=\s*[\"']\s*(?:java\.)?showReadingBrowser\(\s*'([^']+)'\s*,\s*'([^']*)'\s*\)\s*[\"']|[\"']click[\"']\s*:\s*\"\s*(showPara|showChapter)\(\s*'([^']+)'\s*\)\s*\")"#, options: .caseInsensitive)
    private static let count = try! NSRegularExpression(pattern: #"\bcount\s*=\s*[\"']([0-9]{1,8}(?:\.[0-9]{1,2})?[万千kK+]?)[\"']"#, options: .caseInsensitive)
    private static let link = try! NSRegularExpression(pattern: #"\bdata-(paragraph|chapter)-review(?:-url)?\s*=\s*[\"']([^\"']+)[\"']"#, options: .caseInsensitive)
    private static let ident = try! NSRegularExpression(pattern: #"\bident\s*=\s*[\"']((?:https?://|/)[^\"']+)[\"']"#, options: .caseInsensitive)

    static func split(_ html: String, base: URL, paragraphs: (String) -> [String]) -> (text: [String], reviews: [ReaderSourceReview]?) {
        guard html.utf8.count <= 4_194_304,
              ["<comment", "onPress", "showPara(", "showChapter(", "-review"].contains(where: { html.localizedCaseInsensitiveContains($0) })
        else { return (paragraphs(html), nil) }
        let source = html as NSString
        var output = "", cursor = 0, links: [ReaderSourceReview] = []
        let prefix = "\u{E000}" + UUID().uuidString + ":"
        tags.enumerateMatches(in: html, range: NSRange(location: 0, length: source.length)) { match, _, _ in
            guard let range = match?.range, range.length <= 131_072 else { return }
            let tag = ResponseFormatDetector.decodeHTMLEntities(source.substring(with: range))
            guard let parsed = parseTag(tag, base: base) else { return }
            output += source.substring(with: NSRange(location: cursor, length: range.location - cursor))
            if links.count < 512 {
                output += prefix + String(links.count) + "\u{E001}"
                links.append(parsed)
            }
            cursor = NSMaxRange(range)
        }
        guard !links.isEmpty else { return (paragraphs(html), nil) }
        output += source.substring(from: cursor)
        var lines: [String] = [], resolved: [ReaderSourceReview] = []
        for line in paragraphs(output) {
            var cleaned = "", found: [Int] = []
            var remainder = line[...]
            while let start = remainder.range(of: prefix), let end = remainder[start.upperBound...].firstIndex(of: "\u{E001}") {
                cleaned += remainder[..<start.lowerBound]
                if let index = Int(remainder[start.upperBound..<end]), links.indices.contains(index) { found.append(index) }
                remainder = remainder[remainder.index(after: end)...]
            }
            cleaned += remainder
            let body = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { lines.append(body) }
            for index in found where links[index].isChapter || !lines.isEmpty {
                var item = links[index]; item.paragraph = item.isChapter ? -1 : lines.count - 1; resolved.append(item)
            }
        }
        return (lines, resolved.isEmpty ? nil : resolved)
    }

    private static func parseTag(_ tag: String, base: URL) -> ReaderSourceReview? {
        let text = tag as NSString, range = NSRange(location: 0, length: (tag as NSString).length)
        func value(_ m: NSTextCheckingResult, _ index: Int) -> String? {
            m.range(at: index).location == NSNotFound ? nil : text.substring(with: m.range(at: index))
        }
        let target: String, isChapter: Bool
        if let m = link.firstMatch(in: tag, range: range), let scope = value(m, 1), let address = value(m, 2) {
            target = address; isChapter = scope.lowercased() == "chapter"
        } else if let m = action.firstMatch(in: tag, range: range), let name = value(m, 3), let address = value(m, 4) {
            target = address; isChapter = name.lowercased() == "showchapter"
        } else if let m = action.firstMatch(in: tag, range: range), let address = value(m, 1), let title = value(m, 2) {
            isChapter = ["章评", "本章说", "章末", "章说"].contains(where: title.contains)
            guard isChapter || tag.lowercased().hasPrefix("<comment") || title.contains("段评") || title.contains("段说") else { return nil }
            target = address
        } else if tag.lowercased().hasPrefix("<comment"), let m = ident.firstMatch(in: tag, range: range), let address = value(m, 1) {
            target = address; isChapter = false
        } else { return nil }
        guard let url = ReaderSourceReview.webURL(target, base: base) else { return nil }
        let number = count.firstMatch(in: tag, range: range).flatMap { value($0, 1) }
        return .init(url: url, isChapter: isChapter, count: number, paragraph: -1)
    }
}
