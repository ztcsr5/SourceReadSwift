import Foundation

/// A grouped result is a work plus its independently selectable source entries.
struct AggregatedSearchBook: Identifiable, Sendable {
    struct Identity: Hashable, Sendable {
        let title: String
        let author: String
        let mediaKind: BookSourceKind
        let unverifiedEdition: String?
    }

    let id: Identity
    let name: String
    let author: String?
    let intro: String?
    let latestChapter: String?
    let coverProvider: SearchBook?
    let sources: [SearchBook]
    let primaryBook: SearchBook
    let sourceCount: Int

    var selectionTitle: String {
        sourceCount == 1 ? "\(sources.count) 个版本" : "\(sourceCount) 个书源"
    }
}

enum DiscoverSearchAggregation {
    static func group(_ books: [SearchBook], kinds: [String: BookSourceKind]) -> [AggregatedSearchBook] {
        var groups: [AggregatedSearchBook.Identity: [SearchBook]] = [:]
        var order: [AggregatedSearchBook.Identity] = []
        var seen = Set<String>()
        for book in books {
            guard let address = SearchBookMatcher.identityKey(for: book), seen.insert(address).inserted else { continue }
            let title = SearchBookMatcher.cleanTitle(book.name).nilIfEmpty ?? SearchBookMatcher.normalized(book.name)
            let author = SearchBookMatcher.authorIdentity(for: book.author)
            // Same title alone is not enough to merge editions or invent an author.
            let identity = AggregatedSearchBook.Identity(title: title, author: author ?? "",
                mediaKind: book.mediaKind ?? kinds[book.sourceUrl] ?? .text,
                unverifiedEdition: author == nil ? address : nil)
            if groups[identity] == nil { order.append(identity) }
            groups[identity, default: []].append(book)
        }
        return order.compactMap { identity in
            guard let entries = groups[identity], let primary = entries.first else { return nil }
            let cover = entries.first { $0.coverUrl?.nilIfEmpty != nil }
            return AggregatedSearchBook(id: identity, name: primary.name, author: primary.author,
                intro: entries.lazy.compactMap { $0.intro?.nilIfEmpty }.first,
                latestChapter: entries.lazy.compactMap { $0.lastChapter?.nilIfEmpty }.first,
                coverProvider: cover, sources: entries, primaryBook: primary,
                sourceCount: Set(entries.map(\.sourceUrl)).count)
        }
    }
}
