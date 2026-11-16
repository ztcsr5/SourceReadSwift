import CryptoKit
import Foundation

/// Source-scoped script cache with durable text entries and a separate process-only memory cache.
/// Unlike Legado's global keys, separate source URLs cannot read each other's entries.
final class SourceScriptCacheStore: @unchecked Sendable {
    static let shared = SourceScriptCacheStore()

    struct Limits {
        var maximumValueBytes = 1024 * 1024
        var maximumDiskBytes = 16 * 1024 * 1024
        var maximumDiskEntries = 1024
        var maximumMemoryBytes = 8 * 1024 * 1024
        var maximumMemoryEntries = 512
    }

    enum Failure: String, Error {
        case invalidKey = "cache-key-exceeds-limit"
        case invalidLifetime = "cache-lifetime-must-be-finite-seconds"
        case valueLimit = "cache-value-exceeds-limit"
        case corruptEntry = "cache-entry-cannot-be-decoded"
    }

    private struct Entry: Codable {
        let value: String
        let expiresAt: TimeInterval?
    }

    private struct FileEntry {
        let byteCount: Int
        var lastAccess: TimeInterval
        var cached: Entry?
    }

    private struct MemoryEntry {
        let value: String
        var lastAccess: TimeInterval
    }

    private let folderURL: URL
    private let limits: Limits
    private let clock: () -> Date
    private let isPersistent: Bool
    private let lock = NSLock()
    private var hasLoadedCatalog = false
    private var lastAccessTime: TimeInterval = 0
    private var files: [String: FileEntry] = [:]
    private var memory: [String: MemoryEntry] = [:]

    init(rootURL: URL? = nil, limits: Limits = Limits(), clock: @escaping () -> Date = Date.init, isPersistent: Bool = true) {
        folderURL = AppStorageDirectory.appStorageURL(fileName: "source-script-cache-v1", rootURL: rootURL)
        self.limits = limits
        self.clock = clock
        self.isPersistent = isPersistent
    }

    /// Returns durable text; an expired or absent entry is a cache miss.
    func get(_ key: String, scope: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let identifier = try identifier(key, scope: scope)
        try loadCatalog()
        guard var file = files[identifier] else { return nil }
        guard let entry = try loadEntry(identifier, file: file) else { return nil }
        let now = clock().timeIntervalSince1970
        if let expiresAt = entry.expiresAt, expiresAt <= now {
            try removeFile(identifier)
            return nil
        }
        file.lastAccess = nextAccessTime()
        file.cached = entry
        files[identifier] = file
        return entry.value
    }

    /// Writes before acknowledging success; lifetime is in seconds and zero means no expiry.
    func put(_ value: String, for key: String, scope: String, lifetime: TimeInterval = 0) throws {
        lock.lock()
        defer { lock.unlock() }
        try validate(value)
        guard lifetime.isFinite else { throw Failure.invalidLifetime }
        let identifier = try identifier(key, scope: scope)
        try loadCatalog()
        if lifetime < 0 {
            try removeFile(identifier)
            return
        }
        let now = clock().timeIntervalSince1970
        let deadline = lifetime == 0 ? nil : now + lifetime
        if let deadline, !deadline.isFinite { throw Failure.invalidLifetime }
        let entry = Entry(value: value, expiresAt: deadline)
        let bytes = try JSONEncoder().encode(entry)
        guard bytes.count <= limits.maximumDiskBytes, limits.maximumDiskEntries > 0 else {
            throw Failure.valueLimit
        }
        // Admission can fail during eviction; do it before making the new value durable.
        try trimFiles(keeping: identifier, incomingBytes: bytes.count)
        // Only the changed entry is written; large cached HTML pages are not rewritten on every put.
        if isPersistent {
            try bytes.write(to: fileURL(identifier), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
        files[identifier] = FileEntry(byteCount: bytes.count, lastAccess: nextAccessTime(), cached: entry)
    }

    /// Reads a process-only serialized value without accessing persistent storage.
    func getFromMemory(_ key: String, scope: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let identifier = try identifier(key, scope: scope)
        guard var entry = memory[identifier] else { return nil }
        entry.lastAccess = nextAccessTime()
        memory[identifier] = entry
        return entry.value
    }

    /// Stores a bounded process-only value shared by runtimes for this source.
    func putMemory(_ value: String, for key: String, scope: String) throws {
        lock.lock()
        defer { lock.unlock() }
        try validate(value)
        guard value.utf8.count <= limits.maximumMemoryBytes, limits.maximumMemoryEntries > 0 else {
            throw Failure.valueLimit
        }
        let identifier = try identifier(key, scope: scope)
        memory[identifier] = MemoryEntry(value: value, lastAccess: nextAccessTime())
        while memory.count > limits.maximumMemoryEntries || memory.values.reduce(0, { $0 + $1.value.utf8.count }) > limits.maximumMemoryBytes {
            guard let oldest = memory.filter({ $0.key != identifier }).min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            memory.removeValue(forKey: oldest)
        }
    }

    /// Removes only the process-local value; durable entries with this key remain intact.
    @discardableResult
    func deleteMemory(_ key: String, scope: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return memory.removeValue(forKey: try identifier(key, scope: scope))?.value
    }

    /// Deletes both containers, matching Legado's cache.delete contract.
    @discardableResult
    func delete(_ key: String, scope: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        let identifier = try identifier(key, scope: scope)
        try loadCatalog()
        var oldValue: String?
        if let file = files[identifier] {
            do {
                if let entry = try loadEntry(identifier, file: file),
                   entry.expiresAt.map({ $0 > clock().timeIntervalSince1970 }) ?? true {
                    oldValue = entry.value
                }
            } catch Failure.corruptEntry {
                // Deleting corrupt text must still clear the independent memory entry.
            }
        }
        try removeFile(identifier)
        memory.removeValue(forKey: identifier)
        return oldValue
    }

    private var maximumEntryBytes: Int { limits.maximumValueBytes * 6 + 256 }

    private func nextAccessTime() -> TimeInterval {
        // Equal timestamps and wall-clock corrections must not randomize LRU eviction.
        lastAccessTime = max(clock().timeIntervalSince1970, lastAccessTime.nextUp)
        return lastAccessTime
    }

    private func validate(_ value: String) throws {
        guard value.utf8.count <= limits.maximumValueBytes else { throw Failure.valueLimit }
    }

    private func identifier(_ key: String, scope: String) throws -> String {
        guard key.utf8.count <= 4096, scope.utf8.count <= 8192 else { throw Failure.invalidKey }
        // Length-prefixing avoids ambiguous boundaries; file names never contain a source URL or cache key.
        let bytes = Data("\(scope.utf8.count):\(scope)\(key)".utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func fileURL(_ identifier: String) -> URL {
        folderURL.appendingPathComponent(identifier).appendingPathExtension("json")
    }

    private func loadEntry(_ identifier: String, file: FileEntry) throws -> Entry? {
        if let cached = file.cached { return cached }
        let bytes: Data
        do {
            bytes = try Data(contentsOf: fileURL(identifier))
        } catch where isMissingFile(error) {
            files.removeValue(forKey: identifier)
            return nil
        }
        guard bytes.count <= maximumEntryBytes,
              let entry = try? JSONDecoder().decode(Entry.self, from: bytes),
              entry.value.utf8.count <= limits.maximumValueBytes else {
            try removeFile(identifier)
            throw Failure.corruptEntry
        }
        return entry
    }

    private func loadCatalog() throws {
        guard !hasLoadedCatalog else { return }
        guard isPersistent else { hasLoadedCatalog = true; return }
        files.removeAll()
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var folder = folderURL
        try folder.setResourceValues(resourceValues)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for url in try fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: Array(keys)) where url.pathExtension == "json" {
            let identifier = url.deletingPathExtension().lastPathComponent
            guard identifier.count == 64, identifier.allSatisfy({ $0.isHexDigit }) else { continue }
            let attributes = try url.resourceValues(forKeys: keys)
            guard attributes.isRegularFile == true else { continue }
            let byteCount = attributes.fileSize ?? maximumEntryBytes + 1
            if byteCount > maximumEntryBytes {
                try fileManager.removeItem(at: url)
                continue
            }
            let lastAccess = attributes.contentModificationDate?.timeIntervalSince1970 ?? 0
            lastAccessTime = max(lastAccessTime, lastAccess)
            files[identifier] = FileEntry(byteCount: byteCount, lastAccess: lastAccess)
        }
        try trimFiles(keeping: nil)
        hasLoadedCatalog = true
    }

    private func trimFiles(keeping identifier: String?, incomingBytes: Int = 0) throws {
        func exceedsBudget() -> Bool {
            let replacedFile = identifier.flatMap { files[$0] }
            let entryCount = files.count + (identifier != nil && replacedFile == nil ? 1 : 0)
            let byteCount = files.values.reduce(0, { $0 + $1.byteCount }) - (replacedFile?.byteCount ?? 0) + incomingBytes
            return entryCount > limits.maximumDiskEntries || byteCount > limits.maximumDiskBytes
        }
        guard exceedsBudget() else { return }
        let now = clock().timeIntervalSince1970
        for (key, file) in files where key != identifier {
            do {
                if let entry = try loadEntry(key, file: file), let expiry = entry.expiresAt, expiry <= now {
                    try removeFile(key)
                }
            } catch Failure.corruptEntry {
                // A corrupt entry was removed by loadEntry and cannot displace live cache entries.
                continue
            }
        }
        while exceedsBudget() {
            guard let oldest = files.filter({ $0.key != identifier }).min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key else { break }
            try removeFile(oldest)
        }
    }

    private func removeFile(_ identifier: String) throws {
        guard files[identifier] != nil else { return }
        if isPersistent {
            do { try FileManager.default.removeItem(at: fileURL(identifier)) }
            catch where isMissingFile(error) { /* An absent cache entry is already deleted. */ }
        }
        files.removeValue(forKey: identifier)
    }

    private func isMissingFile(_ error: Error) -> Bool {
        let failure = error as NSError
        return failure.domain == NSCocoaErrorDomain &&
            (failure.code == NSFileNoSuchFileError || failure.code == NSFileReadNoSuchFileError)
    }
}
