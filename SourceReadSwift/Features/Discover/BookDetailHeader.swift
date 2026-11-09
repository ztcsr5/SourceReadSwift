import SwiftUI

/// Shared compact identity block; the synopsis belongs below, only once.
struct BookDetailHeader: View {
    let book: SearchBook
    var format: String? = nil
    var readerSourceID: String? = nil
    var readerNamespace: Namespace.ID? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            cover
                .frame(width: 76, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 7) {
                Text(book.name).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(book.author?.nilIfEmpty ?? "作者未知").font(.subheadline).foregroundStyle(.secondary)
                Text(format ?? book.sourceName).font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
                if let count = book.wordCount?.nilIfEmpty {
                    Text(count).font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .podcastCard()
    }

    @ViewBuilder private var cover: some View {
        if let readerSourceID, let readerNamespace {
            coverImage.bookHeroSource(readerSourceID, in: readerNamespace)
        } else {
            coverImage
        }
    }

    @ViewBuilder private var coverImage: some View {
        if let url = CoverURLResolver.url(from: book.coverUrl, base: book.bookUrl, fallbackBase: book.sourceUrl) {
            CachedRemoteImage(url: url, maxPixelSize: 280) { placeholder }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10).fill(AppTheme.accent.opacity(0.1))
            .overlay { Image(systemName: "book.closed").font(.title).foregroundStyle(AppTheme.accent) }
    }
}
