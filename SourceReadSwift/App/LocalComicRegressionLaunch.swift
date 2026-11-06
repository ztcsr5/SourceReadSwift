#if DEBUG
import UIKit
import ZIPFoundation

/// Explicit, isolated CBZ import fixture exercising the production archive and reader.
@MainActor enum LocalComicRegressionLaunch {
    static func makeAppState() -> AppState {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("local-comic-ui-" + UUID().uuidString)
        let shelf = BookshelfStore(persistence: BookshelfPersistence(rootURL: root),
            groupPersistence: BookshelfGroupPersistence(rootURL: root))
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let file = root.appendingPathComponent("CBZ 本地阅读样本.cbz")
            guard let archive = Archive(url: file, accessMode: .create) else { throw LocalComicImportError.invalidArchive }
            for index in 1...6 {
                let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 960)).image { renderer in
                    UIColor.white.setFill()
                    renderer.fill(CGRect(x: 0, y: 0, width: 390, height: 960))
                    ("本地漫画第 \(index) 页" as NSString).draw(at: CGPoint(x: 24, y: 32),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
                }
                guard let bytes = bitmap.pngData() else { throw LocalComicImportError.invalidImage }
                try archive.addEntry(with: "\(index).png", type: .file, uncompressedSize: Int64(bytes.count)) { offset, size in
                    bytes.subdata(in: Int(offset)..<(Int(offset) + size))
                }
            }
            let imported = try LocalComicBookParser(directory: root.appendingPathComponent("LocalComics")).parse(fileURL: file)
            shelf.addLocalTextBook(imported)
            if let book = shelf.books.first { shelf.markReaderOpened(bookID: book.id) }
        } catch { assertionFailure("Local comic fixture could not import its isolated archive: \(error.localizedDescription)") }
        return AppState(sourceStore: SourceStore(persistence: SourcePersistence(rootURL: root)),
            bookshelfStore: shelf, chapterContentCacheStore: ChapterContentCacheStore(persistence: .init(rootURL: root)),
            bookTOCacheStore: BookTOCacheStore(rootURL: root))
    }
}
#endif
