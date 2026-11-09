import Foundation

/// Pure bookshelf ordering used by the screen and by regression tests.
///
/// The shelf used to run this filter/sort chain from the computed property on
/// every body pass, including the pass triggered while returning from a book.
/// Keeping it as one pure function lets the view hold the result and lets the
/// ordering rules be tested without a SwiftUI host.
enum ShelfProjection {
    static func books(
        _ books: [BookshelfBook],
        group: String?,
        media: String?,
        query: String,
        sort: BookshelfView.BookshelfSortMode,
        returnOrder: [String],
        mediaKind: (BookshelfBook) -> BookSourceKind?
    ) -> [BookshelfBook] {
        var list = books

        if let group {
            list = list.filter { $0.groupName == group }
        }

        if let media {
            switch media {
            case "local":
                list = list.filter { $0.sourceURL.hasPrefix("local://") }
            case "comic":
                list = list.filter { mediaKind($0) == .comic }
            case "audio":
                list = list.filter { mediaKind($0) == .audio }
            case "video":
                list = list.filter { mediaKind($0) == .video }
            case "novel":
                list = list.filter {
                    !$0.sourceURL.hasPrefix("local://") && (mediaKind($0) == .text || mediaKind($0) == nil)
                }
            default:
                break
            }
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !normalizedQuery.isEmpty {
            list = list.filter {
                $0.title.lowercased().contains(normalizedQuery) ||
                $0.author.lowercased().contains(normalizedQuery)
            }
        }

        if let anchored = BookReturnOrder.restore(list, ids: returnOrder) { return anchored }
        return list.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            switch sort {
            case .recentRead:
                let lDate = lhs.lastReadAt ?? lhs.addedAt
                let rDate = rhs.lastReadAt ?? rhs.addedAt
                return lDate > rDate
            case .added:
                return lhs.addedAt > rhs.addedAt
            case .title:
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            case .progress:
                return lhs.readingProgress > rhs.readingProgress
            }
        }
    }
}
