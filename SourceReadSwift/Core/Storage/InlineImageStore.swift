import CryptoKit
import Foundation

/// Disk-backed registry for inline illustrations produced by
/// `ruleContent.imageDecode`.
///
/// A chapter paragraph stores only `srdata://inline/<sha256>.<ext>`, which
/// keeps `ChapterContentCacheStore` small and lets the existing reader image
/// loader cache the decoded bitmap without knowing anything about book-source
/// rules. Identical payloads share one file.
final class InlineImageStore: @unchecked Sendable {
    static let shared = InlineImageStore()
    static let scheme = "srdata"
    static let host = "inline"

    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"^[0-9a-f]{64}\.(png|jpg|gif|webp|bmp|heic|avif|tiff)$"#
    )

    private let fileManager: FileManager
    private let directory: URL
    private let lock = NSLock()
    private let maximumStoredBytes: Int64
    private var writesSinceTrim = 0

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        maximumStoredBytes: Int64 = 256 * 1024 * 1024
    ) {
        self.fileManager = fileManager
        self.maximumStoredBytes = max(maximumStoredBytes, 16 * 1024 * 1024)
        self.directory = directory ?? AppStorageDirectory.appStorageURL(
            fileName: "InlineImages",
            fileManager: fileManager
        )
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var writableDirectory = self.directory
        try? writableDirectory.setResourceValues(resourceValues)
    }

    func store(_ payload: InlineImagePayload) -> URL? {
        let digest = SHA256.hash(data: payload.data)
            .map { String(format: "%02x", $0) }
            .joined()
        let fileName = "\(digest).\(payload.fileExtension)"
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)

        if !isCompleteFile(at: fileURL, expectedSize: payload.data.count) {
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try payload.data.write(to: fileURL, options: [.atomic])
            } catch {
                return nil
            }
        }

        scheduleTrimIfNeeded(payload.data.count)

        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        components.path = "/\(fileName)"
        return components.url
    }

    func data(for url: URL) -> Data? {
        guard let fileName = Self.tokenFileName(from: url) else { return nil }
        let fileURL = directory.appendingPathComponent(fileName, isDirectory: false)
        guard let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
              !data.isEmpty,
              data.count <= InlineImageDecoder.maximumByteCount,
              InlineImageDecoder.imageFileExtension(for: data) != nil else {
            return nil
        }
        return data
    }

    static func isInlineURL(_ url: URL) -> Bool {
        tokenFileName(from: url) != nil
    }

    static func tokenFileName(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme,
              components.host?.lowercased() == host,
              components.query == nil,
              components.fragment == nil,
              components.path.hasPrefix("/") else {
            return nil
        }
        let fileName = String(components.path.dropFirst())
        guard !fileName.isEmpty, !fileName.contains("/") else { return nil }
        let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
        guard tokenPattern.firstMatch(in: fileName, range: range) != nil else { return nil }
        return fileName
    }

    /// Test hook: removes stored payloads without touching chapter content.
    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            try? fileManager.removeItem(at: file)
        }
    }

    private func isCompleteFile(at url: URL, expectedSize: Int) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return false
        }
        return size == expectedSize
    }

    private func scheduleTrimIfNeeded(_ byteCount: Int) {
        lock.lock()
        writesSinceTrim += 1
        let shouldTrim = writesSinceTrim >= 64 || byteCount >= 2 * 1024 * 1024
        if shouldTrim {
            writesSinceTrim = 0
        }
        lock.unlock()
        guard shouldTrim else { return }
        trimIfNeeded()
    }

    private func trimIfNeeded() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        var entries: [(url: URL, size: Int64, modified: Date)] = []
        var total: Int64 = 0
        for file in files {
            guard let values = try? file.resourceValues(forKeys: keys),
                  let size = values.fileSize,
                  let modified = values.contentModificationDate else { continue }
            entries.append((file, Int64(size), modified))
            total += Int64(size)
        }
        guard total > maximumStoredBytes else { return }

        let target = maximumStoredBytes * 3 / 4
        for entry in entries.sorted(by: { $0.modified < $1.modified }) {
            try? fileManager.removeItem(at: entry.url)
            total -= entry.size
            if total <= target { break }
        }
    }
}
