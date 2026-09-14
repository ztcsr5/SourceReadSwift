import Foundation

/// Unified storage directory resolver and safe writer for iOS and sandbox environments (e.g. LiveContainer).
enum AppStorageDirectory {
    /// Resolves the storage URL for a given file name, with progressive fallbacks:
    /// 1. rootURL (if provided)
    /// 2. Application Support Directory
    /// 3. Documents Directory (always writable in LiveContainer)
    /// 4. Temporary Directory
    static func appStorageURL(fileName: String, fileManager: FileManager = .default, rootURL: URL? = nil) -> URL {
        if let rootURL {
            return rootURL.appendingPathComponent(fileName)
        }
        let base: URL = {
            if let appSupport = try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ) {
                return appSupport
            }
            if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                return docs
            }
            return fileManager.temporaryDirectory
        }()
        let folder = base.appendingPathComponent("SourceReadSwift", isDirectory: true)
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    /// Safely writes data to destination. Attempts atomic write first, falling back to
    /// direct write if atomic temp file rename fails under sandboxed hooks.
    static func safeWrite(_ data: Data, to url: URL, fileManager: FileManager = .default) throws {
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            try data.write(to: url, options: [.atomic])
        } catch {
            try data.write(to: url)
        }
    }
}
