import Foundation

struct ComicPage: Identifiable, Hashable, Sendable {
    let id: Int
    let url: String
}

enum ComicContentParser {
    static func parsePages(from content: ChapterContent) -> [ComicPage] {
        var urls: [String] = []

        // 1. Check each paragraph for [img]...[/img], markdown ![](), or plain image URLs
        for para in content.paragraphs {
            let imgTokens = extractImgTokens(from: para)
            if !imgTokens.isEmpty {
                urls.append(contentsOf: imgTokens)
                continue
            }

            let mdTokens = extractMarkdownImages(from: para)
            if !mdTokens.isEmpty {
                urls.append(contentsOf: mdTokens)
                continue
            }

            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if isImageURL(trimmed) {
                urls.append(trimmed)
            }
        }

        // 2. If no URLs extracted from paragraphs, check content.text for HTML <img src="..."> tags
        if urls.isEmpty {
            urls = extractImgTags(from: content.text)
        }

        // 3. Fallback: check markdown image tags across full text
        if urls.isEmpty {
            urls = extractMarkdownImages(from: content.text)
        }

        // 4. Fallback: check if content.text is JSON array of strings or objects
        if urls.isEmpty, let data = content.text.data(using: .utf8) {
            if let jsonArr = try? JSONSerialization.jsonObject(with: data) as? [String] {
                urls = jsonArr.filter { isImageURL($0) }
            } else if let jsonDictArr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in jsonDictArr {
                    if let url = (item["url"] as? String ?? item["src"] as? String ?? item["image"] as? String), isImageURL(url) {
                        urls.append(url)
                    }
                }
            }
        }

        // 5. Fallback: split content.text by newline or comma and check for raw URLs
        if urls.isEmpty {
            let rawLines = content.text.components(separatedBy: CharacterSet.newlines)
            for line in rawLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if isImageURL(trimmed) {
                    urls.append(trimmed)
                }
            }
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

    private static func extractMarkdownImages(from text: String) -> [String] {
        var results: [String] = []
        let pattern = #"!\[[^\]]*\]\((https?://[^\)\s]+)\)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
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

    private static func extractImgTags(from html: String) -> [String] {
        var results: [String] = []
        let pattern = #"<img[^>]+(?:src|data-src|data-original|data-url)=["']([^"']+)["']"#
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
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        return true
    }
}
