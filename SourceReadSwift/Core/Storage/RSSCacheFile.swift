import Foundation

private enum RSSCacheWriter {
    static let queue = DispatchQueue(label: "SourceReadSwift.rss-cache.disk", qos: .utility)
}

/// Serializes feed/article snapshots away from UI updates and preserves write order.
struct RSSCacheFile<Snapshot: Codable & Sendable>: Sendable {
    let url: URL
    var onWrite: (@Sendable () -> Void)? = nil

    func load() throws -> Snapshot? {
        try RSSCacheWriter.queue.sync {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Snapshot.self, from: Data(contentsOf: url))
        }
    }

    func save(_ snapshot: Snapshot) {
        RSSCacheWriter.queue.async {
            onWrite?()
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let bytes = try encoder.encode(snapshot)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: url, options: .atomic)
            } catch {
                // Cache failure must not prevent reading, but remains diagnosable.
                NSLog("RSS cache snapshot write failed: code=%ld", (error as NSError).code)
            }
        }
    }

    func waitForPendingWrites() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            RSSCacheWriter.queue.async { continuation.resume() }
        }
    }
}
