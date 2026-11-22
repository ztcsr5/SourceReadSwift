import SwiftUI

/// An entry in source order; the opening book gets room for its jacket and introduction.
struct ExploreBookEntry: View {
    let book: SearchBook
    let sourceKind: BookSourceKind?
    let isLead: Bool
    let isOnShelf: Bool
    let onAdd: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            NavigationLink {
                BookDetailView(book: book)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    if !typeSize.isAccessibilitySize {
                        AsyncBookCover(urlString: book.coverUrl, width: isLead ? 84 : 52, height: isLead ? 114 : 72,
                            baseURLString: book.bookUrl, sourceURLString: book.sourceUrl, title: book.name, cornerRadius: 4)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.name).font(isLead ? .system(.title3, design: .serif).weight(.semibold) : .headline)
                            .foregroundStyle(.primary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        if !byline.isEmpty { Text(byline).font(.subheadline).foregroundStyle(.secondary).lineLimit(2) }
                        if let note = book.intro?.nilIfEmpty ?? book.lastChapter?.nilIfEmpty {
                            Text(note).font(.footnote).foregroundStyle(.secondary).lineLimit(isLead ? 3 : 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel([book.name, byline].filter { !$0.isEmpty }.joined(separator: "，"))
            .accessibilityIdentifier("discover.exploreBook")
            Button(action: onAdd) {
                Image(systemName: isOnShelf ? "checkmark.circle" : "plus.circle")
                    .font(.title3).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(isOnShelf)
            .accessibilityLabel(isOnShelf ? "已在书架，\(book.name)" : "加入书架，\(book.name)")
            .accessibilityIdentifier("discover.exploreShelfAdd")
        }
    }

    private var byline: String {
        let medium = book.mediaKind ?? sourceKind
        return [book.author?.nilIfEmpty, medium == .text ? nil : medium?.displayName, book.wordCount?.nilIfEmpty]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
