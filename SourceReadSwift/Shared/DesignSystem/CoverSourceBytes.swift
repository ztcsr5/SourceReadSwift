import Foundation

/// Briefly shares original encoded bytes across cover sizes. Never stores a
/// thumbnail as a source and never extends HTTP no-store responses.
final class CoverSourceBytes: @unchecked Sendable {
    struct Response: Sendable {
        let bytes: Data
        let freshness: TimeInterval
    }
    private final class Entry {
        let bytes: Data
        let expires: TimeInterval
        init(_ bytes: Data, expires: TimeInterval) {
            self.bytes = bytes
            self.expires = expires
        }
    }
    private struct Transfer {
        let id: UUID
        let task: Task<Data?, Never>
    }
    private static let maximumEntryBytes = 2 * 1024 * 1024
    private static let lifetime: TimeInterval = 300
    private let entries = NSCache<NSURL, Entry>()
    private let lock = NSLock()
    private var transfers: [URL: Transfer] = [:]

    init() {
        entries.countLimit = 12
        entries.totalCostLimit = 12 * 1024 * 1024
    }

    /// Identical public cover URLs share one transfer regardless of decode size.
    func bytes(for url: URL, fetch: @escaping @Sendable () async -> Response?) async -> Data? {
        await transfer(for: url, fetch: fetch).value
    }

    private func transfer(for url: URL, fetch: @escaping @Sendable () async -> Response?) -> Task<Data?, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries.object(forKey: url as NSURL) {
            if entry.expires > ProcessInfo.processInfo.systemUptime {
                let bytes = entry.bytes
                return Task { bytes }
            }
            entries.removeObject(forKey: url as NSURL)
        }
        if let pending = transfers[url] { return pending.task }
        let id = UUID()
        let task = Task<Data?, Never> { [weak self] in
            let response = await fetch()
            return self?.finish(url: url, id: id, response: response)
        }
        transfers[url] = Transfer(id: id, task: task)
        return task
    }

    private func finish(url: URL, id: UUID, response: Response?) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        guard transfers[url]?.id == id else { return nil }
        transfers[url] = nil
        guard !Task.isCancelled, let response else { return nil }
        if response.freshness > 0, response.bytes.count <= Self.maximumEntryBytes {
            let entry = Entry(response.bytes, expires: ProcessInfo.processInfo.systemUptime + response.freshness)
            entries.setObject(entry, forKey: url as NSURL, cost: response.bytes.count)
        }
        return response.bytes
    }

    /// The temporary byte cache never extends the server's explicit lifetime.
    static func freshness(cacheControl: String, age: String?, hasExplicitExpiry: Bool) -> TimeInterval {
        let directives = cacheControl.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if directives.contains(where: { $0.hasPrefix("no-cache") || $0.hasPrefix("no-store") || $0.hasPrefix("private") }) { return 0 }
        if let maxAge = directives.first(where: { $0.hasPrefix("max-age=") }) {
            let value = maxAge.dropFirst("max-age=".count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard let seconds = TimeInterval(value), seconds.isFinite else { return 0 }
            return min(lifetime, max(0, seconds - max(0, TimeInterval(age ?? "") ?? 0)))
        }
        return hasExplicitExpiry ? 0 : lifetime
    }

    /// A failed decode must not prevent a later network retry.
    func invalidate(_ url: URL, matching bytes: Data) {
        lock.lock()
        defer { lock.unlock() }
        if entries.object(forKey: url as NSURL)?.bytes == bytes { entries.removeObject(forKey: url as NSURL) }
    }

    /// Cancel transfers and invalidate their ownership before dropping memory.
    func clear() {
        lock.lock()
        let pending = Array(transfers.values)
        transfers.removeAll()
        entries.removeAllObjects()
        lock.unlock()
        for transfer in pending { transfer.task.cancel() }
    }
}
