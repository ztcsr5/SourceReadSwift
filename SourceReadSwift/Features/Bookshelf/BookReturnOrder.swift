import Foundation

/// Preserve visible source slots, not stale book values, while returning from a book.
enum BookReturnOrder {
    static func restore(_ books: [BookshelfBook], ids: [String]) -> [BookshelfBook]? {
        guard !ids.isEmpty, ids.count == books.count else { return nil }
        let byID = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = ids.compactMap { byID[$0] }
        return ordered.count == books.count ? ordered : nil
    }
}
