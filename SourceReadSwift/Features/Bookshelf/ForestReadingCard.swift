import SwiftUI

/// The book carries the depth. The glass is one quiet backing, not a plinth.
struct ForestReadingCard: View {
    let book: BookshelfBook
    let heroNamespace: Namespace.ID?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 22
    var theme: AppVisualTheme = .forest
    private let bookHeight: CGFloat = 156

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 18))
        layout {
            jacket.frame(width: 116)
            readingInformation
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { BrandGlass(outline: RoundedRectangle(cornerRadius: 24, style: .continuous)) }
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点继续阅读，使用更多操作管理")
    }

    @ViewBuilder private var jacket: some View {
        let cover = EditorialBookJacket(height: bookHeight, palette: .resolve(theme: theme), stance: .floating) {
            AsyncBookCover(urlString: book.coverURL, width: 103, height: bookHeight,
                baseURLString: book.bookURL, sourceURLString: book.sourceURL,
                title: book.title, prefersDeskRaster: true, cornerRadius: 3, usesPlainPlaceholder: true)
        }
        // The matched source clips its capture on iOS 18. Measure the jacket
        // together with its page edge and shadow, rather than the raw bitmap.
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
        if let heroNamespace { cover.bookHeroSource("continue|" + book.id, in: heroNamespace) }
        else { cover }
    }

    private var readingInformation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(book.title)
                .font(ReadingDeskTitleTypography.font(size: titleSize))
                .foregroundStyle(theme.primaryInk)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, typeSize.isAccessibilitySize ? 0 : 36)
            if let author = book.author.nilIfEmpty {
                Text(author).font(.subheadline).foregroundStyle(theme.secondaryInk)
                    .lineLimit(1).padding(.top, 5)
                    .padding(.trailing, typeSize.isAccessibilitySize ? 0 : 24)
            }

            VStack(alignment: .leading, spacing: 4) {
                if book.lastReadAt != nil {
                    Text("上次读到").font(.caption).foregroundStyle(theme.secondaryInk)
                    Text(book.currentChapterTitle?.nilIfEmpty ?? ReadingDeskContent.contextLine(for: book))
                        .font(.subheadline.weight(.medium)).foregroundStyle(theme.primaryInk)
                        .lineLimit(2)
                    if book.totalChapters > 0 {
                        Text(ReadingHeroStatus.progress(for: book)).font(.caption.monospacedDigit())
                            .foregroundStyle(AppTheme.accent).padding(.top, 4)
                    }
                } else {
                    Text(ReadingDeskContent.contextLine(for: book))
                        .font(.subheadline).foregroundStyle(theme.secondaryInk).lineLimit(3)
                }
            }
            .padding(.top, 14)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: typeSize.isAccessibilitySize ? nil : bookHeight, alignment: .leading)
    }
}
