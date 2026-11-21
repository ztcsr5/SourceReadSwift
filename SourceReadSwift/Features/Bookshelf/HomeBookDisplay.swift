import SwiftUI

/// The active home arrangements share cover loading and book-opening actions.
struct HomeBookDisplay<BookLabel: View>: View {
    let style: HomeBookPresentation
    let books: [BookshelfBook]
    @Binding var selection: String?
    let theme: AppVisualTheme
    let mediaKind: (BookshelfBook) -> BookSourceKind?
    let onOpenBook: (BookshelfBook) -> Void
    @ViewBuilder let bookLabel: (BookshelfBook, CGFloat, CGFloat) -> BookLabel
    @Environment(\.dynamicTypeSize) private var typeSize

    private var activeBook: BookshelfBook? {
        books.first { $0.id == selection } ?? books.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if style == .showcase {
                HomeBookCarousel(books: books, selection: $selection,
                    layout: .init(widthFraction: 0.68, height: 330, centered: true)) { book, width in
                    let coverWidth = min(width * 0.82, 240)
                    bookAction(book) {
                        bookLabel(book, coverWidth, coverWidth / 0.78)
                            .shadow(color: theme.primaryInk.opacity(0.14), radius: 8, y: 6)
                    }
                }
                .padding(.top, 32)
                if let activeBook { showcaseMetadata(for: activeBook).padding(.top, 16) }
            } else if style == .journal, let lead = books.first {
                Text("继续阅读").font(.headline.weight(.bold)).foregroundStyle(theme.primaryInk)
                    .padding(.top, 28).padding(.bottom, 16).padding(.horizontal, AppTheme.pagePadding)
                journalCard(lead).padding(.horizontal, AppTheme.pagePadding)
            }
        }
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.bookDisplay." + style.rawValue)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.weekday(.wide))
                .font(.caption).foregroundStyle(theme.secondaryInk)
            Text(Date.now, format: .dateTime.month().day())
                .font(.system(style == .journal ? .title : .largeTitle).weight(.bold))
        }
        .foregroundStyle(theme.primaryInk)
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 24)
    }

    private func journalCard(_ book: BookshelfBook) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return VStack(alignment: .leading, spacing: 12) {
            Button { onOpenBook(book) } label: {
                layout {
                    bookLabel(book, 80, 120)
                    VStack(alignment: .leading, spacing: 6) {
                        Text((resolvedMediaKind(for: book)?.displayName ?? BookSourceKind.text.displayName)
                            + " · " + ReadingHeroStatus.progressValue(for: book))
                            .font(.caption).foregroundStyle(theme.secondaryInk)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(book.title)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(theme.primaryInk)
                                .lineLimit(2)
                            mediaIcon(for: book, color: theme.secondaryInk)
                        }
                        if let author = book.author.nilIfEmpty {
                            Text(author)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryInk)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 12)
                        Label(ReadingHeroStatus.chapter(for: book), systemImage: "bookmark")
                            .font(.caption).foregroundStyle(theme.secondaryInk).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bookshelf.continue." + book.id)

            progressRail(for: book)

            HStack(spacing: 8) {
                Button { onOpenBook(book) } label: {
                    Label("继续阅读", systemImage: "book")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(theme.primaryInk)
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 44)

                if resolvedMediaKind(for: book) == .audio {
                    Button { onOpenBook(book) } label: {
                        Label("听书", systemImage: "headphones")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(theme.primaryInk)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.card)
                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
        }
        .accessibilityElement(children: .contain)
    }

    private func showcaseMetadata(for book: BookshelfBook) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.author.nilIfEmpty ?? "作者未记录")
                .font(.subheadline).foregroundStyle(theme.secondaryInk).lineLimit(1)
            Text(book.title).font(.title2.weight(.bold)).foregroundStyle(theme.primaryInk).lineLimit(2)
            Text(ReadingHeroStatus.chapter(for: book))
                .font(.caption).foregroundStyle(theme.secondaryInk).lineLimit(1)
            HStack(spacing: 8) {
                progressRail(for: book).frame(width: 110)
                Text(ReadingHeroStatus.progressValue(for: book))
                    .font(.caption.monospacedDigit()).foregroundStyle(theme.secondaryInk)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 32)
    }

    private func progressRail(for book: BookshelfBook) -> some View {
        GeometryReader { geometry in
            let fraction = book.readingProgress.isFinite ? min(max(book.readingProgress, 0), 1) : 0
            let minimum = book.lastReadAt == nil ? CGFloat(0) : CGFloat(4)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.primaryInk.opacity(0.14))
                Capsule().fill(theme.primaryInk)
                    .frame(width: min(geometry.size.width, max(minimum, geometry.size.width * fraction)))
            }
        }
        .frame(height: 4)
        .accessibilityLabel("阅读进度")
        .accessibilityValue(ReadingHeroStatus.progressValue(for: book))
    }

    private func mediaIcon(for book: BookshelfBook, color: Color) -> some View {
        let kind = resolvedMediaKind(for: book) ?? .text
        return Image(systemName: kind.systemImage).font(.caption2.weight(.semibold))
            .foregroundStyle(color).accessibilityLabel(kind.displayName)
    }

    private func bookAction<Content: View>(_ book: BookshelfBook, @ViewBuilder content: () -> Content) -> some View {
        Button { onOpenBook(book) } label: { content().contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bookshelf.continue." + book.id)
            .accessibilityLabel(book.title)
            .accessibilityHint("打开书籍")
    }

    private func resolvedMediaKind(for book: BookshelfBook) -> BookSourceKind? {
        mediaKind(book) ?? book.mediaKind
    }
}
