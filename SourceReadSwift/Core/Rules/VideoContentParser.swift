import Foundation

enum VideoContentParser {
    static func parseVideoURL(from content: ChapterContent, chapterURL: String? = nil) -> String? {
        let text = content.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Direct .m3u8, .mp4, .flv, .mov in text
        let extensions = [".m3u8", ".mp4", ".flv", ".mov", ".m4v"]
        for ext in extensions {
            if let range = text.range(of: ext, options: .caseInsensitive) {
                let prefix = text[..<range.upperBound]
                if let httpIdx = prefix.range(of: "http", options: [.backwards, .caseInsensitive])?.lowerBound {
                    let candidate = String(text[httpIdx..<range.upperBound])
                    if URL(string: candidate) != nil {
                        return candidate
                    }
                }
            }
        }

        // 2. HTML <video src="..."> or <source src="...">
        let srcPattern = #"(?:<video|<source)[^>]+src=["']([^"']+)["']"#
        if let regex = try? NSRegularExpression(pattern: srcPattern, options: .caseInsensitive) {
            let nsString = text as NSString
            if let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsString.length)),
               match.numberOfRanges > 1 {
                let candidate = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.hasPrefix("http") {
                    return candidate
                }
            }
        }

        // 3. JSON with "url" or "playUrl" key
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let videoUrl = json["url"] as? String ?? json["playUrl"] as? String ?? json["video"] as? String {
            return videoUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 4. Plain URL in text
        if text.hasPrefix("http://") || text.hasPrefix("https://") {
            let firstLine = text.components(separatedBy: .newlines).first ?? text
            return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 5. Fallback: check chapterURL itself
        if let chapterURL, chapterURL.hasPrefix("http") && (chapterURL.contains(".m3u8") || chapterURL.contains(".mp4")) {
            return chapterURL
        }

        return nil
    }
}
