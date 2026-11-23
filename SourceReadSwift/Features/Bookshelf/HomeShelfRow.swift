import SwiftUI

/// Optional home shelf. The center book reads directly; the side books first change the preview.
struct HomeShelfRow<BookLabel: View, LibraryLink: View>: View {
    let books: [BookshelfBook]
    @Binding var selection: String?
    let theme: AppVisualTheme
    let onOpenBook: (BookshelfBook) -> Void
    @ViewBuilder let bookLabel: (BookshelfBook, CGFloat, CGFloat) -> BookLabel
    @ViewBuilder let libraryLink: () -> LibraryLink
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24
    @AppMotion private var motion

    private var activeBook: BookshelfBook? {
        books.first { $0.id == selection } ?? books.first
    }

    private var rowBooks: [BookshelfBook] {
        guard books.count >= 3 else { return books }
        // Start with a neighbor on each side, without duplicating an item in the scroll view.
        return [books[2], books[0], books[1]] + Array(books.dropFirst(3))
    }

    var body: some View {
        if let book = activeBook {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 16) {
                    title(for: book)
                        .padding(.horizontal, AppTheme.pagePadding)
                    shelf(for: book)
                }
                .padding(.top, 16)
                .background { upperMist }
                resume(book)
                    .padding(.horizontal, AppTheme.pagePadding)
            }
            .padding(.bottom, 24)
            .accessibilityIdentifier("home.bookDisplay.shelfRow")
        }
    }

    private func title(for book: BookshelfBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("手边的书")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                libraryLink()
            }
            .foregroundStyle(theme.secondaryInk)
            Text(book.title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(theme.primaryInk)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("home.shelfRow.title")
            if let author = book.author.nilIfEmpty {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryInk)
            }
        }
    }

    @ViewBuilder private var upperMist: some View {
        if !reducesTransparency, contrast != .increased, theme == .forest || theme == .coverGlass {
            AppPagePaper(theme: theme)
                .mask {
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
                .ignoresSafeArea(edges: .top)
        }
    }

    private func shelf(for currentBook: BookshelfBook) -> some View {
        GeometryReader { geometry in
            let width = min(152, geometry.size.width * 0.38)
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .bottom, spacing: 12) {
                        ForEach(rowBooks) { book in
                            jacket(book, width: currentBook.id == book.id ? width : width * 0.62,
                                isCurrent: currentBook.id == book.id)
                                .id(book.id)
                        }
                    }
                    .padding(.horizontal, AppTheme.pagePadding)
                    .padding(.bottom, 8)
                    .frame(minWidth: geometry.size.width, maxHeight: .infinity, alignment: .bottom)
                }
                .scrollIndicators(.hidden)
                .onAppear { scroll.scrollTo(currentBook.id, anchor: .center) }
                .onChange(of: currentBook.id) { id in
                    withAnimation(motion.animation(.navigation)) {
                        scroll.scrollTo(id, anchor: .center)
                    }
                }
                .accessibilityIdentifier("home.shelfRow.covers")
            }
        }
        .frame(height: 208)
        .overlay(alignment: .bottom) {
            ReadingDeskFrontEdge(palette: .resolve(theme: theme)).frame(height: 5)
        }
    }

    private func jacket(_ book: BookshelfBook, width: CGFloat, isCurrent: Bool) -> some View {
        Button {
            if isCurrent { onOpenBook(book) }
            else { selection = book.id }
        } label: {
            bookLabel(book, width, width / 0.78)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(book.title)
        .accessibilityHint(isCurrent ? "打开书籍" : "预览这本书")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityIdentifier((isCurrent ? "bookshelf.continue." : "home.shelfRow.preview.") + book.id)
    }

    private func resume(_ book: BookshelfBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ReadingHeroStatus.chapter(for: book))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(theme.primaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let fraction = AtelierReadingProgress.fraction(for: book) {
                HStack(spacing: 8) {
                    ProgressView(value: Double(fraction))
                        .tint(theme.primaryInk)
                        .frame(maxWidth: 120)
                        .accessibilityLabel("阅读进度")
                    Text(ReadingHeroStatus.progressValue(for: book))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryInk)
                        .accessibilityHidden(true)
                }
            }
            Button {
                onOpenBook(book)
            } label: {
                HStack(spacing: 8) {
                    Text(book.lastReadAt == nil ? "开始阅读" : "继续阅读")
                    Image(systemName: "arrow.right").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.prominentInk)
                .frame(minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(AppTheme.prominentFill)
            .controlSize(.large)
            .accessibilityIdentifier("home.shelfRow.continue")
        }
    }
}
