import Foundation

struct SourcePersistence {
    private let fileManager: FileManager
    private let fileName = "book_sources.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> SourceLibrarySnapshot {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return SourceLibrarySnapshot()
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let snapshot = try? decoder.decode(SourceLibrarySnapshot.self, from: data) {
            return snapshot
        }
        let legacySources = try decoder.decode([BookSource].self, from: data)
        return SourceLibrarySnapshot(sources: legacySources)
    }

    func save(_ sources: [BookSource]) throws {
        try save(SourceLibrarySnapshot(sources: sources))
    }

    func save(_ snapshot: SourceLibrarySnapshot) throws {
        let url = try storageURL()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        try AppStorageDirectory.safeWrite(data, to: url, fileManager: fileManager)
    }

    private func storageURL() throws -> URL {
        AppStorageDirectory.appStorageURL(fileName: fileName, fileManager: fileManager, rootURL: rootURL)
    }
}
