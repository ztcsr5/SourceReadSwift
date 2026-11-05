import CryptoKit
import Foundation
import ImageIO

/// Committed manga images, kept separately from disposable reader caches.
actor ComicOfflineArchive {
    static let shared = ComicOfflineArchive()
    static let maximumPageBytes = 24 * 1024 * 1024
    private static let maximumChapterBytes = 256 * 1024 * 1024
    private static let maximumPages = 600
    private static let archiveScheme = "srcomic"
    private static let manifestFileName = "chapter.json"

    typealias PageFetcher = @Sendable (ComicImageRequest) async -> Result<Data, ComicImageFailure>

    enum Failure: LocalizedError {
        case incompleteChapter, chapterTooLarge, page(Int, ComicImageFailure)

        var errorDescription: String? {
            switch self {
            case .incompleteChapter: return "本话未解析完整，不能保存为离线漫画。"
            case .chapterTooLarge: return "本话超出离线存储上限。"
            case .page(let index, let failure): return "第 \(index) 页：\(failure.message)"
            }
        }
    }

    private struct Manifest: Codable {
        let chapterIndex: Int
        let title: String
        let pages: [Page]

        struct Page: Codable {
            let size: Int
            let digest: String
        }
    }

    private let root: URL
    private let fileManager: FileManager
    private var clearGeneration = 0
    private var cleanedStaging = false

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.root = directory ?? AppStorageDirectory.appStorageURL(fileName: "OfflineComics", fileManager: fileManager)
    }

    /// Reopens validated images in saved order without any network dependency.
    func pages(sourceURL: String, chapter: BookChapter) -> [ComicPage]? {
        let folder = chapterDirectory(sourceURL: sourceURL, chapter: chapter)
        guard let manifest = readManifest(at: folder, verifyDigests: true) else { return nil }
        return manifest.pages.indices.map { index in
            ComicPage(id: index, url: pageURL(index, in: folder).absoluteString)
        }
    }

    /// Rechecks actual image bytes before reporting a previous download as complete.
    func contains(sourceURL: String, chapter: BookChapter) -> Bool {
        readManifest(at: chapterDirectory(sourceURL: sourceURL, chapter: chapter), verifyDigests: true) != nil
    }

    func hasManifest(sourceURL: String, chapter: BookChapter) -> Bool {
        fileManager.fileExists(atPath: chapterDirectory(sourceURL: sourceURL, chapter: chapter)
            .appendingPathComponent(Self.manifestFileName).path)
    }

    /// Provides a sparse offline TOC when the online directory cache is absent.
    func chapters(sourceURL: String, bookURL: String) -> [BookChapter] {
        let book = bookDirectory(sourceURL: sourceURL, bookURL: bookURL)
        return directories(in: book).compactMap { folder in
            guard let manifest = readManifest(at: folder, verifyDigests: false) else { return nil }
            let token = "\(Self.archiveScheme)://chapter/\(folder.lastPathComponent)"
            return BookChapter(title: manifest.title, url: token, bookUrl: bookURL, index: manifest.chapterIndex)
        }.sorted { $0.index < $1.index }
    }

    /// Persists one complete chapter; partial or cancelled writes never become visible.
    func save(_ content: ChapterContent, sourceURL: String, headers: [String: String], fetch: PageFetcher) async throws {
        let resources = ComicChapterResources(content: content)
        guard resources.canReuseFromCache else { throw Failure.incompleteChapter }
        guard resources.pages.count <= Self.maximumPages else { throw Failure.chapterTooLarge }
        let destination = chapterDirectory(sourceURL: sourceURL, chapter: content.chapter)
        if readManifest(at: destination, verifyDigests: true) != nil { return }
        let generation = clearGeneration
        if !fileManager.fileExists(atPath: root.path) {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            var directory = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            do { try directory.setResourceValues(values) }
            catch { NSLog("Could not exclude offline comic files from backup: %ld", (error as NSError).code) }
        }
        let stagingRoot = root.appendingPathComponent(".staging", isDirectory: true)
        if !cleanedStaging {
            if fileManager.fileExists(atPath: stagingRoot.path) { try fileManager.removeItem(at: stagingRoot) }
            cleanedStaging = true
        }
        let staging = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer {
            if fileManager.fileExists(atPath: staging.path) {
                do { try fileManager.removeItem(at: staging) }
                catch { NSLog("Could not remove staged offline comic files: %ld", (error as NSError).code) }
            }
        }

        var entries: [Manifest.Page] = []
        var storedBytes = 0
        for page in resources.pages {
            try checkIsCurrent(generation)
            let image = ComicImageRequest(url: page.url, headers: page.headers)
            let request = ComicImageRequest(url: page.url,
                headers: image.mergingHeaders(headers, chapterURL: content.chapter.url))
            let result = await fetch(request)
            try checkIsCurrent(generation)
            let bytes: Data
            switch result {
            case .success(let received): bytes = received
            case .failure(let failure): throw Failure.page(page.id + 1, failure)
            }
            guard bytes.count <= Self.maximumPageBytes else { throw Failure.page(page.id + 1, .tooLarge) }
            guard Self.canDecode(bytes) else { throw Failure.page(page.id + 1, .invalidImage) }
            storedBytes += bytes.count
            guard storedBytes <= Self.maximumChapterBytes else { throw Failure.chapterTooLarge }
            try bytes.write(to: pageURL(page.id, in: staging), options: [.atomic])
            entries.append(.init(size: bytes.count, digest: Self.digest(bytes)))
        }

        try checkIsCurrent(generation)
        let manifest = Manifest(chapterIndex: content.chapter.index, title: String(content.title.prefix(512)), pages: entries)
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent(Self.manifestFileName), options: [.atomic])
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Another task may have completed the same edition during a network await.
        if readManifest(at: destination, verifyDigests: true) != nil { return }
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try fileManager.moveItem(at: staging, to: destination)
    }

    /// Explicit user cleanup; ordinary reader-cache eviction does not call this.
    func removeAll() throws {
        clearGeneration &+= 1
        guard fileManager.fileExists(atPath: root.path) else { return }
        try fileManager.removeItem(at: root)
    }

    func storageSummary() -> (chapterCount: Int, bytes: Int64) {
        var chapterCount = 0
        var bytes: Int64 = 0
        for book in directories(in: root) {
            for chapter in directories(in: book) {
                guard let manifest = readManifest(at: chapter, verifyDigests: false) else { continue }
                chapterCount += 1
                bytes += manifest.pages.reduce(0) { $0 + Int64($1.size) }
            }
        }
        return (chapterCount, bytes)
    }

    private func checkIsCurrent(_ generation: Int) throws {
        try Task.checkCancellation()
        guard generation == clearGeneration else { throw CancellationError() }
    }

    private func readManifest(at folder: URL, verifyDigests: Bool) -> Manifest? {
        let file = folder.appendingPathComponent(Self.manifestFileName)
        guard let bytes = try? Data(contentsOf: file), bytes.count <= 128 * 1024,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: bytes),
              !manifest.pages.isEmpty, manifest.pages.count <= Self.maximumPages else { return nil }
        for (index, entry) in manifest.pages.enumerated() {
            let image = pageURL(index, in: folder)
            guard entry.size > 0, entry.size <= Self.maximumPageBytes,
                  let values = try? image.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true, values.fileSize == entry.size else { return nil }
            if verifyDigests {
                guard let bytes = try? Data(contentsOf: image, options: .mappedIfSafe),
                      Self.digest(bytes) == entry.digest else { return nil }
            }
        }
        return manifest
    }

    private func directories(in folder: URL) -> [URL] {
        let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                            options: [.skipsHiddenFiles])) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private func bookDirectory(sourceURL: String, bookURL: String) -> URL {
        root.appendingPathComponent(Self.digest(Data("\(sourceURL.utf8.count):\(sourceURL)\(bookURL)".utf8)), isDirectory: true)
    }

    private func chapterDirectory(sourceURL: String, chapter: BookChapter) -> URL {
        let book = bookDirectory(sourceURL: sourceURL, bookURL: chapter.bookUrl)
        let identifier = Self.offlineIdentifier(chapter.url) ?? Self.digest(Data(chapter.url.utf8))
        return book.appendingPathComponent(identifier, isDirectory: true)
    }

    private func pageURL(_ index: Int, in folder: URL) -> URL {
        folder.appendingPathComponent("page-\(index).img")
    }

    private static func offlineIdentifier(_ address: String) -> String? {
        guard let url = URL(string: address), url.scheme == archiveScheme, url.host == "chapter" else { return nil }
        let name = url.lastPathComponent
        return name.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil ? name : nil
    }

    static func isOfflineChapter(_ chapter: BookChapter) -> Bool { offlineIdentifier(chapter.url) != nil }

    private static func digest(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func canDecode(_ bytes: Data) -> Bool {
        guard !bytes.isEmpty, let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return false }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options) != nil
    }
}
