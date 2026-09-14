import Foundation

struct BookshelfPersistence {
    private let fileManager: FileManager
    private let fileName = "bookshelf_books.json"
    private let rootURL: URL?

    init(fileManager: FileManager = .default, rootURL: URL? = nil) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func load() throws -> [BookshelfBook] {
        let url = try storageURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([BookshelfBook].self, from: data)
    }

    func save(_ books: [BookshelfBook]) throws {
        let url = try storageURL()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(books)
        try AppStorageDirectory.safeWrite(data, to: url, fileManager: fileManager)
    }

    private func storageURL() throws -> URL {
        AppStorageDirectory.appStorageURL(fileName: fileName, fileManager: fileManager, rootURL: rootURL)
    }
}
