import Foundation

/// Remembers which sources already produced a matching book for a title.
///
/// Every source switch used to start a fresh 40-source search, so the user
/// stared at a progress list even when the exact same search had completed a
/// minute earlier. Cached candidates are shown immediately; a background
/// refresh still runs so a newly added source can appear.
@MainActor
final class SourceSwitchCacheStore {
    static let shared = SourceSwitchCacheStore()

    struct Candidate: Codable, Equatable, Sendable {
        var sourceURL: String
        var sourceName: String
        var book: SearchBook
    }

    private struct Entry: Codable, Equatable, Sendable {
        var key: String
        var cachedAt: Date
        var candidates: [Candidate]
    }

    private let fileURL: URL
    private let ttl: TimeInterval
    private var entries: [String: Entry] = [:]

    init(
        fileURL: URL = AppStorageDirectory.appStorageURL(fileName: "source_switch_cache.json"),
        ttl: TimeInterval = 7 * 24 * 60 * 60
    ) {
        self.fileURL = fileURL
        self.ttl = ttl
        load()
    }

    static func key(title: String, author: String?) -> String {
        normalizedKeyPart(title) + "|" + normalizedKeyPart(author ?? "")
    }

    /// Width/case folding alone still left the ASCII space from `ＴＥＳＴ 书名`
    /// in the key, so the same search could miss its cache. Strip whitespace
    /// and punctuation as well; neither is meaningful for a title lookup.
    private static func normalizedKeyPart(_ raw: String) -> String {
        let folded = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "zh_Hans"))
        let ignored = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        return String(folded.unicodeScalars.filter { !ignored.contains($0) }.map { Character($0) })
    }

    func candidates(title: String, author: String?) -> [Candidate]? {
        let key = Self.key(title: title, author: author)
        guard let entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.cachedAt) <= ttl else {
            entries.removeValue(forKey: key)
            persist()
            return nil
        }
        return entry.candidates
    }

    func save(title: String, author: String?, candidates: [Candidate]) {
        guard !candidates.isEmpty else { return }
        let key = Self.key(title: title, author: author)
        entries[key] = Entry(key: key, cachedAt: Date(), candidates: candidates)
        // Keep the file bounded; ten recent searches are enough for a reader.
        if entries.count > 10 {
            let keep = entries
                .sorted { $0.value.cachedAt > $1.value.cachedAt }
                .prefix(10)
            entries = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        guard let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        entries = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? AppStorageDirectory.safeWrite(data, to: fileURL)
    }
}
