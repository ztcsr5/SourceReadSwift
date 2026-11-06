import Foundation
import UIKit

struct BookExportService: Sendable {
    init() {}

    func exportBookToPlainText(
        book: BookshelfBook,
        cachedChapters: [ChapterContent],
        includeIntro: Bool = true
    ) throws -> URL {
        var output = ""

        output += "《\(book.title)》\n"
        output += "作者：\(book.author)\n"
        output += "书源：\(book.sourceName)\n"
        output += "导出时间：\(Date().formatted(date: .numeric, time: .shortened))\n"
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
            let ordered = cachedChapters.enumerated().sorted {
                if $0.element.chapter.index != $1.element.chapter.index {
                    return $0.element.chapter.index < $1.element.chapter.index
                }
                return $0.offset < $1.offset
            }
            for (_, chapter) in ordered {
                let chapterTitle = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let number = max(0, min(chapter.chapter.index, Int.max - 1)) + 1
                output += "第 \(number) 章 \(chapterTitle)\n\n"
                for para in chapter.paragraphs {
                    let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    output += "    \(trimmed)\n\n"
                }
                output += "\n"
            }
        }

        let sanitizedTitle = book.title
            .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Leave room for the unique suffix within a 255-byte filesystem component.
        var titlePrefix = ""
        for character in sanitizedTitle {
            guard titlePrefix.utf8.count + String(character).utf8.count <= 180 else { break }
            titlePrefix.append(character)
        }
        let fileName = "\(titlePrefix.isEmpty ? "书籍导出" : titlePrefix)-\(UUID().uuidString).txt"

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try output.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}
