import Foundation

struct ComicPage: Identifiable, Hashable, Sendable {
    let id: Int
    let url: String
}

enum ComicContentParser {
    static func parsePages(from content: ChapterContent) -> [ComicPage] {
        var urls: [String] = []

        // 1. Check each paragraph for [img]...[/img] tokens
        for para in content.paragraphs {
            let matches = extractImgTokens(from: para)
            if !matches.isEmpty {
                urls.append(contentsOf: matches)
            } else {
                let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
                if isImageURL(trimmed) {
                    urls.append(trimmed)
                }
            }
        }

        // 2. If no URLs extracted, check content.text for HTML <img src="..."> tags
        if urls.isEmpty {
            let fullText = content.text
            urls = extractImgTags(from: fullText)
        }

        // 3. Fallback: check if content.text is JSON array of strings
        if urls.isEmpty, let data = content.text.data(using: .utf8),
           let jsonArr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            urls = jsonArr.filter { isImageURL($0) }
        }

        // Deduplicate consecutive identical URLs
        var deduped: [String] = []
        for url in urls {
            if deduped.last != url {
                deduped.append(url)
            }
        }

        return deduped.enumerated().map { index, url in
            ComicPage(id: index, url: url)
        }
    }

    private static func extractImgTokens(from text: String) -> [String] {
        var results: [String] = []
        var searchRange = text.startIndex..<text.endIndex
        while let open = text.range(of: "[img]", range: searchRange),
              let close = text.range(of: "[/img]", range: open.upperBound..<text.endIndex) {
            let url = String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !url.isEmpty {
                results.append(url)
            }
            searchRange = close.upperBound..<text.endIndex
        }
        return results
    }

    private static func extractImgTags(from html: String) -> [String] {
        var results: [String] = []
        let pattern = #"<img[^>]+(?:src|data-src|data-original)=["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let nsString = html as NSString
            let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let url = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if isImageURL(url) {
                        results.append(url)
                    }
                }
            }
        }
        return results
    }

    private static func isImageURL(_ str: String) -> Bool {
        let lower = str.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }
}
