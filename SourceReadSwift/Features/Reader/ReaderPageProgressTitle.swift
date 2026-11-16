import Foundation

/// Formats chapter progress from one page's immutable position, including prewarmed neighbours.
enum ReaderPageProgressTitle {
    static func format(chapterIndex: Int, chapterTitle: String, totalChapters: Int?, pageStatus: String?) -> String {
        var parts: [String] = []
        if let totalChapters, totalChapters > 0 {
            let percentage = Int((Double(chapterIndex + 1) / Double(totalChapters) * 100).rounded())
            let chapterNumber = min(max(declaredChapterNumber(in: chapterTitle) ?? (chapterIndex + 1), 1), totalChapters)
            parts.append("第 \(chapterNumber) / \(totalChapters) 章")
            parts.append("\(percentage)%")
        } else {
            parts.append("第 \(chapterIndex + 1) 章")
        }
        if let pageStatus, !pageStatus.isEmpty { parts.append(pageStatus) }
        return parts.joined(separator: " · ")
    }

    private static func declaredChapterNumber(in title: String) -> Int? {
        guard let range = title.range(of: #"第\s*[0-9]+\s*章"#, options: .regularExpression) else { return nil }
        let digits = title[range].filter(\.isNumber)
        guard let value = Int(digits), value > 0 else { return nil }
        return value
    }
}
