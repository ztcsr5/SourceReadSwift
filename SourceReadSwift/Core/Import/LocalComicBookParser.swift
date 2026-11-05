import Foundation
import ImageIO
import ZIPFoundation

enum LocalComicImportError: LocalizedError {
    case invalidArchive, unsafePath, emptyArchive, resourceLimit, invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidArchive: return "无法打开 CBZ 文件，请确认它是未加密的 ZIP 漫画包。"
        case .unsafePath: return "漫画包包含不安全或重复的路径，请重新导出文件。"
        case .emptyArchive: return "漫画包中没有支持的图片。"
        case .resourceLimit: return "漫画包超过限制：600 页、单图 24 MB、总计 256 MB。"
        case .invalidImage: return "漫画包包含无法解码的图片，未导入部分内容。"
        }
    }
}

/// Imports ordered CBZ pages into an app-owned atomic directory, never ZIP paths.
struct LocalComicBookParser {
    private let directory: URL?
    private static let maximumPageBytes = 24 * 1024 * 1024
    private static let maximumBookBytes = 256 * 1024 * 1024
    private static let extensions: Set<String> = ["jpg", "jpeg", "png", "webp", "gif", "heic", "avif"]

    init(directory: URL? = nil) { self.directory = directory }

    func parse(fileURL: URL) throws -> LocalTextBook {
        let attributes = try fileURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = attributes.fileSize, size > 0 else { throw LocalComicImportError.invalidArchive }
        guard size <= Self.maximumBookBytes else {
            throw LocalComicImportError.resourceLimit
        }
        guard let archive = Archive(url: fileURL, accessMode: .read) else { throw LocalComicImportError.invalidArchive }
        var paths: [String] = []
        var visited = Set<String>()
        var entryCount = 0
        for entry in archive {
            entryCount += 1
            guard entryCount <= 5000 else { throw LocalComicImportError.resourceLimit }
            guard entry.type != .symlink else { throw LocalComicImportError.unsafePath }
            if entry.type == .directory { continue }
            let path = entry.path.replacingOccurrences(of: "\\", with: "/")
            guard path.count <= 2048, !path.hasPrefix("/"), !path.contains("\0"),
                  !path.split(separator: "/").contains(".."), !path.contains(":") else {
                throw LocalComicImportError.unsafePath
            }
            if path.hasPrefix("__MACOSX/") || path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) { continue }
            guard Self.extensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { continue }
            guard visited.insert(path).inserted else { throw LocalComicImportError.unsafePath }
            paths.append(entry.path)
            guard paths.count <= 600 else { throw LocalComicImportError.resourceLimit }
        }
        guard !paths.isEmpty else { throw LocalComicImportError.emptyArchive }
        let locale = Locale(identifier: "en_US_POSIX")
        paths.sort {
            let order = $0.compare($1, options: [.numeric, .caseInsensitive], range: nil, locale: locale)
            return order == .orderedSame ? $0 < $1 : order == .orderedAscending
        }
        let root = try Self.storageDirectory(directory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let identity = UUID().uuidString
        let staging = root.appendingPathComponent(".import-" + identity, isDirectory: true)
        let destination = root.appendingPathComponent(identity, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: staging) } }
        var totalBytes = 0
        var paragraphs: [String] = []
        for (index, path) in paths.enumerated() {
            try Task.checkCancellation()
            guard let entry = archive[path] else { throw LocalComicImportError.invalidArchive }
            guard entry.uncompressedSize <= UInt64(Self.maximumPageBytes) else {
                throw LocalComicImportError.resourceLimit
            }
            var pageBytes = Data()
            let checksum = try archive.extract(entry) { chunk in
                guard chunk.count <= Self.maximumPageBytes - pageBytes.count,
                      chunk.count <= Self.maximumBookBytes - totalBytes else {
                    throw LocalComicImportError.resourceLimit
                }
                pageBytes.append(chunk)
                totalBytes += chunk.count
            }
            guard checksum == entry.checksum else { throw LocalComicImportError.invalidArchive }
            try Self.validateImage(pageBytes)
            let name = String(format: "%04d.img", index)
            try pageBytes.write(to: staging.appendingPathComponent(name), options: .atomic)
            paragraphs.append("[img]\(destination.appendingPathComponent(name).absoluteString)[/img]")
        }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
        committed = true
        let title = String(fileURL.deletingPathExtension().lastPathComponent.prefix(160))
        return LocalTextBook(title: title, author: "本地漫画",
            chapters: [.init(title: title, paragraphs: paragraphs, index: 0)],
            coverURL: destination.appendingPathComponent("0000.img"), mediaKind: .comic)
    }

    static func removeFiles(for book: BookshelfBook, directory: URL? = nil) throws {
        guard book.sourceURL == "local://comic", let address = book.coverURL,
              let cover = URL(string: address), cover.isFileURL else { return }
        let folder = cover.deletingLastPathComponent().resolvingSymlinksInPath()
        let root = try storageDirectory(directory).resolvingSymlinksInPath()
        guard UUID(uuidString: folder.lastPathComponent) != nil,
              folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
        if FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    private static func storageDirectory(_ directory: URL?) throws -> URL {
        if let directory { return directory }
        return try FileManager.default.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SourceReadSwift/LocalComics", isDirectory: true)
    }

    private static func validateImage(_ bytes: Data) throws {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 32,
                kCGImageSourceShouldCache: false
              ] as CFDictionary) != nil else { throw LocalComicImportError.invalidImage }
    }
}
