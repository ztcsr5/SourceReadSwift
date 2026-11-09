import Foundation
import UIKit
import ZIPFoundation

struct BookArchiveExport: Sendable {
    let url: URL
    let exportedChapterCount: Int
    let totalChapterCount: Int
    var isPartial: Bool { exportedChapterCount < totalChapterCount }
}

enum BookExportError: LocalizedError, Equatable {
    case noContent
    case archiveCreationFailed
    case chapterTooLarge

    var errorDescription: String? {
        switch self {
        case .noContent:
            return "本书还没有可导出的正文。请先在目录中缓存章节，或阅读几章后再导出。"
        case .archiveCreationFailed:
            return "无法创建 ZIP 文件，请重试。"
        case .chapterTooLarge:
            return "正文超过单个 ZIP 条目的 4 GB 上限，无法导出。"
        }
    }
}

struct BookExportService: Sendable {
    init() {}

    /// 单本导出：`正文.txt` + `cover.jpg`（有封面时）+ `metadata.json`。
    /// 只写入调用方已经拿到的章节，不在这里发网络请求，避免导出按钮长时间转圈。
    func exportBookArchive(
        book: BookshelfBook,
        cachedChapters: [ChapterContent],
        coverJPEG: Data?,
        totalChapterCount: Int = 0
    ) throws -> BookArchiveExport {
        guard !cachedChapters.isEmpty else { throw BookExportError.noContent }

        let ordered = Self.ordered(cachedChapters)
        let text = plainText(book: book, cachedChapters: ordered, includeIntro: true)
        guard let textData = text.data(using: .utf8) else { throw BookExportError.noContent }

        let metadata = BookArchiveMetadata(
            title: book.title,
            author: book.author,
            sourceName: book.sourceName,
            sourceURL: book.sourceURL,
            bookURL: book.bookURL,
            intro: book.intro,
            exportedAt: Date(),
            exportedChapterCount: ordered.count,
            totalChapterCount: max(totalChapterCount, ordered.count),
            chapters: ordered.map {
                BookArchiveMetadata.Chapter(index: $0.chapter.index, title: $0.title)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let metadataData = try encoder.encode(metadata)

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.fileName(for: book))
        try? FileManager.default.removeItem(at: tempURL)
        guard let archive = Archive(url: tempURL, accessMode: .create) else {
            throw BookExportError.archiveCreationFailed
        }
        try addEntry("正文.txt", data: textData, to: archive)
        if let coverJPEG, !coverJPEG.isEmpty {
            try addEntry("cover.jpg", data: coverJPEG, to: archive)
        }
        try addEntry("metadata.json", data: metadataData, to: archive)

        return BookArchiveExport(url: tempURL,
            exportedChapterCount: ordered.count,
            totalChapterCount: max(totalChapterCount, ordered.count))
    }

    func exportBookToPlainText(
        book: BookshelfBook,
        cachedChapters: [ChapterContent],
        includeIntro: Bool = true
    ) throws -> URL {
        let output = plainText(book: book, cachedChapters: Self.ordered(cachedChapters),
            includeIntro: includeIntro)
        let fileName = Self.uniqueFileName(for: book, extension: "txt")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try output.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }

    private func addEntry(_ name: String, data: Data, to archive: Archive) throws {
        try archive.addEntry(
            with: name,
            type: .file,
            uncompressedSize: Int64(data.count),
            compressionMethod: .deflate,
            provider: { position, size in
                let start = Int(position)
                let end = min(start + size, data.count)
                guard start < end else { return Data() }
                return data.subdata(in: start..<end)
            }
        )
    }

    private func plainText(
        book: BookshelfBook,
        cachedChapters: [ChapterContent],
        includeIntro: Bool
    ) -> String {
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
            for chapter in cachedChapters {
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
        return output
    }

    private static func ordered(_ chapters: [ChapterContent]) -> [ChapterContent] {
        chapters.enumerated().sorted {
            if $0.element.chapter.index != $1.element.chapter.index {
                return $0.element.chapter.index < $1.element.chapter.index
            }
            return $0.offset < $1.offset
        }.map(\.element)
    }

    private static func fileName(for book: BookshelfBook) -> String {
        let sanitizedTitle = sanitized(book.title)
        let stamp = Int(Date().timeIntervalSince1970)
        return "\(sanitizedTitle.isEmpty ? "书籍导出" : sanitizedTitle)-\(stamp)-\(UUID().uuidString.prefix(8)).zip"
    }

    private static func uniqueFileName(for book: BookshelfBook, extension suffix: String) -> String {
        let sanitizedTitle = sanitized(book.title)
        return "\(sanitizedTitle.isEmpty ? "书籍导出" : sanitizedTitle)-\(UUID().uuidString).\(suffix)"
    }

    private static func sanitized(_ title: String) -> String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters))
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var prefix = ""
        for character in cleaned {
            guard prefix.utf8.count + String(character).utf8.count <= 180 else { break }
            prefix.append(character)
        }
        return prefix
    }
}

private struct BookArchiveMetadata: Codable {
    struct Chapter: Codable {
        let index: Int
        let title: String
    }

    let title: String
    let author: String
    let sourceName: String
    let sourceURL: String
    let bookURL: String
    let intro: String?
    let exportedAt: Date
    let exportedChapterCount: Int
    let totalChapterCount: Int
    let chapters: [Chapter]
}
