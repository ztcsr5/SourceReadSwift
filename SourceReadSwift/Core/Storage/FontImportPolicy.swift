import Foundation

/// File-provider type labels are advisory; validate the actual selection at the IO boundary.
enum FontImportPolicy {
    static let maximumBytes = 64 * 1024 * 1024
    static let extensions: Set<String> = ["ttf", "otf", "ttc", "otc", "woff"]
    static func validate(suffix: String, bytes: Int) throws {
        guard extensions.contains(suffix.lowercased()) else {
            throw NSError(domain: "FontImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择 TTF、OTF、TTC 或 OTC 字体文件，不要选择压缩包。"])
        }
        guard bytes > 0, bytes <= maximumBytes else {
            throw NSError(domain: "FontImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "字体文件必须非空且不超过 64 MB。"])
        }
    }
}

/// Shares registered font locations without coupling storage to the reader renderer.
enum CustomFontLocations {
    private static let lock = NSLock()
    private static var files: [String: URL] = [:]
    private static var generation = 0
    private static var completedInitialScan = false
    static var revision: Int { lock.lock(); defer { lock.unlock() }; return generation }
    static var hasCompletedInitialScan: Bool { lock.lock(); defer { lock.unlock() }; return completedInitialScan }
    static func markInitialScanCompleted() {
        lock.lock(); defer { lock.unlock() }
        completedInitialScan = true
    }
    static func register(postScriptName: String, file: URL) {
        lock.lock(); defer { lock.unlock() }
        if files[postScriptName] != file { files[postScriptName] = file; generation &+= 1 }
    }
    static func file(for name: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return files[name]
    }
    static func remove(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        if files.removeValue(forKey: name) != nil { generation &+= 1 }
    }
}
