import Foundation

/// Normalises a chapter before it reaches any reader surface.
///
/// Many Legado sources put the chapter heading into the content body as its
/// first paragraph. Rendering that paragraph with body typography produced
/// three visible defects at once: the heading looked like body text, the real
/// heading (page header) appeared twice, and sources with an empty `title`
/// rule showed no heading at all. This type strips the duplicate, recovers a
/// missing heading from the body, and guarantees a usable display title.
enum ChapterTextSanitizer {
    struct Result: Equatable {
        let title: String
        let paragraphs: [String]
        let removedLeadingTitleCount: Int
        let recoveredTitleFromBody: Bool
    }

    private static let placeholderKeys: Set<String> = [
        "", "正文", "内容", "章节内容", "本章内容", "无标题", "未知", "暂无标题",
        "null", "nil", "undefined", "none", "untitled", "chapter", "text"
    ]

    static func normalize(
        title: String,
        paragraphs: [String],
        fallbackTitle: String = ""
    ) -> Result {
        var body = paragraphs.compactMap(cleanParagraph)
        var resolved = normalizeTitle(title)
        var removed = 0
        var recovered = false

        // A blank/generic title plus a short, heading-shaped first paragraph is
        // the standard "title rule returned nothing" shape in Legado sources.
        if isPlaceholder(resolved),
           body.count > 1,
           let first = body.first,
           looksLikeChapterTitle(first) {
            resolved = normalizeTitle(first)
            body.removeFirst()
            removed += 1
            recovered = true
        }

        if !isPlaceholder(resolved) {
            let key = comparisonKey(resolved)
            while let first = body.first {
                let firstKey = comparisonKey(first)
                if firstKey == key {
                    body.removeFirst()
                    removed += 1
                    continue
                }
                if firstKey.hasPrefix(key) {
                    let remainder = firstKey.dropFirst(key.count)
                    if remainder.count <= 6 {
                        body.removeFirst()
                        removed += 1
                        continue
                    }
                }
                break
            }
        }

        if isPlaceholder(resolved) {
            resolved = normalizeTitle(fallbackTitle)
        }

        // Some paginated sources repeat the heading at the top of every page.
        // Only the first few paragraphs are scanned so a legitimate short line
        // deep inside the chapter is never removed.
        if !resolved.isEmpty {
            let key = comparisonKey(resolved)
            var index = 0
            var scanned = 0
            while index < body.count, scanned < 4 {
                if comparisonKey(body[index]) == key {
                    body.remove(at: index)
                } else {
                    index += 1
                }
                scanned += 1
            }
        }

        return Result(
            title: resolved,
            paragraphs: body,
            removedLeadingTitleCount: removed,
            recoveredTitleFromBody: recovered
        )
    }

    static func normalizeTitle(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let wrappers = CharacterSet(charactersIn: "《》「」『』\"“”'‘’【】()（）[]")
        while let first = text.unicodeScalars.first, wrappers.contains(first) {
            text.removeFirst()
        }
        while let last = text.unicodeScalars.last, wrappers.contains(last) {
            text.removeLast()
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes the BOM, NBSP and the source's own full-width indent. The reader
    /// applies its own two-character indent, so keeping the source indent made
    /// paragraphs start at different x positions and look ragged.
    private static func cleanParagraph(_ raw: String) -> String? {
        var text = raw
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let scalar = text.unicodeScalars.first,
              CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.value == 0x3000 {
            text.removeFirst()
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func isPlaceholder(_ text: String) -> Bool {
        placeholderKeys.contains(comparisonKey(text).lowercased())
    }

    private static func comparisonKey(_ text: String) -> String {
        let folded = text.folding(
            options: [.widthInsensitive, .caseInsensitive],
            locale: Locale(identifier: "zh_Hans")
        )
        let ignored = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(.symbols)
        return String(folded.unicodeScalars.filter { !ignored.contains($0) }.map { Character($0) })
    }

    private static func looksLikeChapterTitle(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 48 else { return false }
        if trimmed.range(
            of: #"^第\s*[0-9零一二三四五六七八九十百千万两]+\s*[章节回卷部篇集]"#,
            options: .regularExpression
        ) != nil {
            return true
        }
        if trimmed.range(
            of: #"^(序章|序言|楔子|引子|前言|后记|尾声|终章|番外|Chapter\s*\d+)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil {
            return true
        }
        return false
    }
}
