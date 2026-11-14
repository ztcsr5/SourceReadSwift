import Foundation

/// Pure Markdown & Plain Text exporter for bookmarks.
enum BookmarkExporter {
    static func markdown(
        bookTitle: String,
        author: String? = nil,
        bookmarks: [ReaderBookmark]
    ) -> String {
        let sorted = sortedBookmarks(bookmarks)
        var lines: [String] = ["# 《\(bookTitle)》书签摘录"]
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            lines.append("\n作者：\(author)")
        }
        lines.append("\n共 \(sorted.count) 条书签 · 导出于 \(timestampString(Date()))\n")
        for item in sorted {
            let loc = locationLabel(for: item)
            lines.append("## \(item.chapterTitle)")
            lines.append("- **位置**：\(loc)")
            lines.append("- **时间**：\(timestampString(item.createdAt))")
            let snippet = item.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty {
                lines.append("\n> \(snippet.replacingOccurrences(of: "\n", with: "\n> "))\n")
            } else {
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func plainText(
        bookTitle: String,
        author: String? = nil,
        bookmarks: [ReaderBookmark]
    ) -> String {
        let sorted = sortedBookmarks(bookmarks)
        var lines: [String] = ["《\(bookTitle)》书签摘录"]
        if let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            lines.append("作者：\(author)")
        }
        lines.append("共 \(sorted.count) 条 · 导出于 \(timestampString(Date()))")
        lines.append(String(repeating: "-", count: 28))
        for (idx, item) in sorted.enumerated() {
            lines.append("\(idx + 1). [\(locationLabel(for: item))] \(item.chapterTitle) (\(timestampString(item.createdAt)))")
            let snippet = item.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
            if !snippet.isEmpty {
                lines.append("   \(snippet)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func markdownAllBooks(_ books: [BookshelfBook]) -> String {
        let withMarks = books.filter { !($0.bookmarks ?? []).isEmpty }
        guard !withMarks.isEmpty else { return "# 纸间书签\n\n暂无书签。" }
        return withMarks.map { book in
            markdown(bookTitle: book.title, author: book.author, bookmarks: book.bookmarks ?? [])
        }.joined(separator: "\n\n---\n\n")
    }

    static func plainTextAllBooks(_ books: [BookshelfBook]) -> String {
        let withMarks = books.filter { !($0.bookmarks ?? []).isEmpty }
        guard !withMarks.isEmpty else { return "暂无书签。" }
        return withMarks.map { book in
            plainText(bookTitle: book.title, author: book.author, bookmarks: book.bookmarks ?? [])
        }.joined(separator: "\n\n==============================\n\n")
    }

    static func writeTemporaryExport(content: String, filename: String, fileExtension: String) throws -> URL {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let safeName = filename.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safeName.isEmpty ? "bookmarks" : safeName
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(base).\(fileExtension)")
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func sortedBookmarks(_ list: [ReaderBookmark]) -> [ReaderBookmark] {
        list.sorted { lhs, rhs in
            if lhs.chapterIndex != rhs.chapterIndex { return lhs.chapterIndex < rhs.chapterIndex }
            if (lhs.paragraphIndex ?? -1) != (rhs.paragraphIndex ?? -1) {
                return (lhs.paragraphIndex ?? -1) < (rhs.paragraphIndex ?? -1)
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private static func locationLabel(for item: ReaderBookmark) -> String {
        if let p = item.paragraphIndex {
            return "第 \(item.chapterIndex + 1) 章 · 第 \(p + 1) 段"
        }
        return "第 \(item.chapterIndex + 1) 章"
    }

    private static func timestampString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: date)
    }
}

/// In-book keyword search hit pointing to a specific chapter and paragraph.
struct ReaderInBookSearchHit: Identifiable, Equatable, Sendable {
    var id: String { "\(chapterIndex):\(paragraphIndex)" }
    let chapterIndex: Int
    let chapterTitle: String
    let paragraphIndex: Int
    let previewText: String
}

struct ReaderInBookSearchChapterSource: Sendable {
    let chapterIndex: Int
    let title: String
    let paragraphs: [String]
}

enum ReaderInBookSearchEngine {
    static func search(
        query: String,
        sources: [ReaderInBookSearchChapterSource],
        limit: Int = 120
    ) -> [ReaderInBookSearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        var hits: [ReaderInBookSearchHit] = []
        let sorted = sources.sorted { $0.chapterIndex < $1.chapterIndex }
        for chapter in sorted {
            for (paragraphIndex, rawText) in chapter.paragraphs.enumerated() {
                if rawText.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                    let clean = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                    hits.append(ReaderInBookSearchHit(
                        chapterIndex: chapter.chapterIndex,
                        chapterTitle: chapter.title,
                        paragraphIndex: paragraphIndex,
                        previewText: excerpt(from: clean, matching: needle)
                    ))
                    if hits.count >= limit { return hits }
                }
            }
        }
        return hits
    }

    private static func excerpt(from text: String, matching needle: String) -> String {
        guard text.count > 90 else { return text }
        guard let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return String(text.prefix(90)) + "…"
        }
        let start = text.index(range.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 48, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = start > text.startIndex ? "…" : ""
        let suffix = end < text.endIndex ? "…" : ""
        return prefix + String(text[start..<end]) + suffix
    }
}
