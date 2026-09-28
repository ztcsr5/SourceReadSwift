import Foundation
import UIKit

public struct BookExportService: Sendable {
    public init() {}

    public func exportBookToPlainText(
        book: BookshelfBook,
        cachedChapters: [ChapterContent],
        includeIntro: Bool = true
    ) throws -> URL {
        var output = ""

        output += "《\(book.title)》\n"
        output += "作者：\(book.author)\n"
        output += "书源：\(book.sourceName)\n"
        if let lastReadAt = book.lastReadAt {
            output += "导出时间：\(lastReadAt.formatted(date: .numeric, time: .shortened))\n"
        }
        output += "\n"

        if includeIntro, let intro = book.intro, !intro.isEmpty {
            output += "【内容简介】\n"
            output += intro.trimmingCharacters(in: .whitespacesAndNewlines)
            output += "\n\n"
        }

        output += String(repeating: "=", count: 40) + "\n\n"

        if cachedChapters.isEmpty {
            output += "（暂无已缓存章节正文内容）\n"
        } else {
            for (idx, chapter) in cachedChapters.enumerated() {
                let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
                output += "第 \(idx + 1) 章 \(chapterTitle)\n\n"
                for para in chapter.paragraphs {
                    let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    output += "    \(trimmed)\n\n"
                }
                output += "\n"
            }
        }

        let sanitizedTitle = book.title
            .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|"))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = "\(sanitizedTitle.isEmpty ? "书籍导出" : sanitizedTitle).txt"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try output.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}
