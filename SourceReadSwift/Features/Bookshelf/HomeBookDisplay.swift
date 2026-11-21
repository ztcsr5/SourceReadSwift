import SwiftUI

/// The five reference arrangements reuse the shelf's cover cache and opening action.
struct HomeBookDisplay<BookLabel: View>: View {
    let style: HomeBookPresentation
    let books: [BookshelfBook]
    @Binding var selection: String?
    let theme: AppVisualTheme
    let mediaKind: (BookshelfBook) -> BookSourceKind?
    let onOpenBook: (BookshelfBook) -> Void
    @ViewBuilder let bookLabel: (BookshelfBook, CGFloat, CGFloat, Bool) -> BookLabel

    @AppMotion private var motion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var spineWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var spineHeight: CGFloat = 156
    @ScaledMetric(relativeTo: .body) private var carouselTextHeight: CGFloat = 96

    private var activeBook: BookshelfBook? {
        books.first { $0.id == selection } ?? books.first
    }

    var body: some View {
        display
            .frame(maxWidth: .infinity)
            .environment(\.locale, Locale(identifier: "zh_CN"))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.bookDisplay." + style.rawValue)
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            switch style {
            case .current, .classic:
                EmptyView()
            case .showcase:
                VStack(alignment: .leading, spacing: 20) {
                    carousel(widthFraction: 0.76, height: 330, centered: true, scales: true) { book, width in
                        bookLabel(book, width * 0.72, width * 0.96, false)
                    }
                    if let activeBook { showcaseMetadata(for: activeBook) }
                }
                .padding(.top, 48)
            case .journal:
                journalBooks
            case .sculptural:
                carousel(widthFraction: 1, height: 184 + carouselTextHeight, centered: true) { book, _ in
                    VStack(alignment: .center, spacing: 20) {
                        bookLabel(book, 120, 160, false)
                        sculpturalMetadata(for: book)
                    }
                }
                .padding(.top, 32)
                pageIndicator.padding(.top, 12)
            case .magazine:
                shelf(isSpine: false)
            case .library:
                shelf(isSpine: true)
            }
        }
        .padding(.bottom, style == .journal ? 16 : 32)
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch style {
            case .showcase, .journal:
                Text(Date.now, format: .dateTime.weekday(.wide))
                    .font(.caption).foregroundStyle(theme.secondaryInk)
                Text(Date.now, format: .dateTime.month().day())
                    .font(.system(style == .journal ? .title : .largeTitle, design: .default).weight(.bold))
            case .sculptural:
                Text("今日阅读。")
                    .font(.system(.title2, design: .serif).weight(.heavy))
                Text(Date.now, format: .dateTime.month().day().weekday())
                    .font(.caption).foregroundStyle(theme.secondaryInk)
            case .magazine:
                editionHeading("阅读特刊", eyebrow: Text("ISSUE · ") + Text(Date.now, format: .dateTime.month().day()))
                Rectangle().fill(theme.primaryInk).frame(height: 1)
            case .library:
                editionHeading("书房阅览室", eyebrow: Text("私人馆藏 · ARCHIVE"))
                Text(Date.now, format: .dateTime.month().day())
                    .font(.caption).foregroundStyle(theme.secondaryInk)
            case .current, .classic:
                EmptyView()
            }
        }
        .foregroundStyle(theme.primaryInk)
        .accessibilityAddTraits(.isHeader)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.pagePadding)
        .padding(.top, 24)
    }

    private func editionHeading(_ title: String, eyebrow: Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            eyebrow.font(.caption2.weight(.bold)).tracking(1.2)
            Text(title).font(.system(.title, design: .serif).weight(.heavy))
        }
    }

    private var journalBooks: some View {
        VStack(alignment: .leading, spacing: 16) {
            heading("继续阅读").padding(.horizontal, AppTheme.pagePadding)
            if let lead = books.first {
                journalCard(lead)
                    .padding(.horizontal, AppTheme.pagePadding)
            }
            if books.count > 1 {
                carousel(Array(books.dropFirst()), widthFraction: 0.78, height: max(112, carouselTextHeight), centered: false) { book, width in
                    compactCard(book, width: width)
                }
            }
        }
        .padding(.top, 28)
    }

    private func journalCard(_ book: BookshelfBook) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
        return VStack(alignment: .leading, spacing: 12) {
            Button { onOpenBook(book) } label: {
                layout {
                    bookLabel(book, 80, 120, false)
                    VStack(alignment: .leading, spacing: 6) {
                        Text((resolvedMediaKind(for: book)?.displayName ?? BookSourceKind.text.displayName)
                            + " · " + ReadingHeroStatus.progressValue(for: book))
                            .font(.caption).foregroundStyle(theme.secondaryInk)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(book.title)
                                .font(.headline.weight(.semibold))
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

            ProgressView(value: book.readingProgress)
                .tint(theme.primaryInk)
                .frame(maxWidth: .infinity)

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

    private func compactCard(_ book: BookshelfBook, width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            bookLabel(book, 56, 84, false)
            VStack(alignment: .leading, spacing: 8) {
                Text(book.title).font(.subheadline.weight(.semibold)).foregroundStyle(theme.primaryInk).lineLimit(2)
                if let author = book.author.nilIfEmpty {
                    Text(author).font(.caption).foregroundStyle(theme.secondaryInk).lineLimit(1)
                }
                Text(ReadingHeroStatus.chapter(for: book))
                    .font(.caption2).foregroundStyle(theme.secondaryInk).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            mediaIcon(for: book, color: theme.primaryInk, font: .body)
                .frame(width: 36, height: 36)
                .background(theme.controlFill, in: Circle())
        }
        .padding(12)
        .frame(width: width, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppTheme.card).shadow(color: .black.opacity(0.06), radius: 6, y: 3)
        }
    }

    private func shelf(isSpine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                heading(isSpine ? "馆藏书架" : "本期在读")
                Spacer()
                Text(isSpine ? "ON SHELF" : "FEATURED")
                    .font(.caption2.weight(.bold)).tracking(1.0).foregroundStyle(theme.secondaryInk)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: isSpine ? .bottom : .top, spacing: isSpine ? 8 : 16) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        bookAction(book) {
                            if isSpine {
                                bookLabel(book, spineWidth + CGFloat(index % 3) * 3,
                                    spineHeight - CGFloat((index + 1) % 3) * 8, true)
                            } else {
                                VStack(alignment: .leading, spacing: 16) {
                                    bookLabel(book, 120, 160, false)
                                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                                        Text(book.title).font(.caption).lineLimit(2)
                                        mediaIcon(for: book, color: theme.secondaryInk)
                                    }
                                    .foregroundStyle(theme.secondaryInk)
                                }
                                .frame(width: 120, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("home.books.horizontalShelf")
            .background(alignment: .top) {
                if !isSpine {
                    Rectangle().fill(theme.controlBorder).frame(height: 6)
                        .shadow(color: theme.primaryInk.opacity(0.12), radius: 4, y: 4)
                        .offset(y: 168)
                }
            }
            .overlay(alignment: .bottom) {
                if isSpine {
                    Rectangle().fill(theme.controlBorder).frame(height: 6)
                        .shadow(color: theme.primaryInk.opacity(0.12), radius: 4, y: 4)
                }
            }
        }
        .padding(.top, 34)
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.headline.weight(.bold)).foregroundStyle(theme.primaryInk).accessibilityAddTraits(.isHeader)
    }

    private func mediaIcon(for book: BookshelfBook, color: Color, font: Font = .caption2.weight(.semibold)) -> some View {
        let kind = resolvedMediaKind(for: book) ?? .text
        return Image(systemName: kind.systemImage)
            .font(font)
            .foregroundStyle(color)
            .accessibilityLabel(kind.displayName)
    }

    private func showcaseMetadata(for book: BookshelfBook) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(book.author.nilIfEmpty ?? "作者未记录")
                    .font(.caption).foregroundStyle(theme.secondaryInk).lineLimit(1)
                Text(book.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(theme.primaryInk).lineLimit(2)
                Text(ReadingHeroStatus.chapter(for: book))
                    .font(.caption2).foregroundStyle(theme.secondaryInk).lineLimit(1)
                HStack(spacing: 6) {
                    ProgressView(value: book.readingProgress)
                        .tint(theme.primaryInk)
                    Text(ReadingHeroStatus.progressValue(for: book))
                        .font(.caption2.monospacedDigit()).foregroundStyle(theme.secondaryInk)
                }
                .frame(maxWidth: 180)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            bookAction(book) {
                mediaIcon(for: book, color: AppTheme.background, font: .title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(theme.primaryInk, in: Circle())
            }
        }
        .padding(.horizontal, 32)
    }

    private func sculpturalMetadata(for book: BookshelfBook) -> some View {
        VStack(spacing: 6) {
            Text(book.title).font(.headline.weight(.bold)).foregroundStyle(theme.primaryInk).lineLimit(2)
            Text((book.author.nilIfEmpty ?? "作者未记录") + " · " + ReadingHeroStatus.progressValue(for: book))
                .font(.caption).foregroundStyle(theme.secondaryInk).lineLimit(2)
        }
        .padding(.horizontal, AppTheme.pagePadding)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private func bookAction<Content: View>(_ book: BookshelfBook, @ViewBuilder content: () -> Content) -> some View {
        Button { onOpenBook(book) } label: {
            content().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("bookshelf.continue." + book.id)
        .accessibilityLabel(book.title)
        .accessibilityHint("打开书籍")
    }

    private var pageIndicator: some View {
        HStack(spacing: 4) {
            ForEach(books) { book in
                let isActive = book.id == activeBook?.id
                Capsule().fill(theme.primaryInk.opacity(isActive ? 0.82 : 0.20))
                    .frame(width: isActive ? 12 : 3, height: 3)
            }
        }
        .animation(motion.animation(.navigation), value: activeBook?.id)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func resolvedMediaKind(for book: BookshelfBook) -> BookSourceKind? {
        mediaKind(book) ?? book.mediaKind
    }

    private func carousel<Card: View>(
        _ entries: [BookshelfBook]? = nil, widthFraction: CGFloat, height: CGFloat,
        centered: Bool, scales: Bool = false, @ViewBuilder card: @escaping (BookshelfBook, CGFloat) -> Card
    ) -> some View {
        HomeBookCarousel(books: entries ?? books, selection: $selection,
            layout: .init(widthFraction: widthFraction, height: height, centered: centered, scales: scales)) { book, width in
                bookAction(book) { card(book, width) }
            }
    }
}

private struct HomeBookCarousel<Card: View>: View {
    struct Layout {
        let widthFraction: CGFloat
        let height: CGFloat
        let centered: Bool
        let scales: Bool
    }

    let books: [BookshelfBook]
    @Binding var selection: String?
    let layout: Layout
    @ViewBuilder let card: (BookshelfBook, CGFloat) -> Card
    @AppMotion private var motion

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width, 560) * layout.widthFraction
            let margin = layout.centered ? max((geometry.size.width - width) / 2, 0) : AppTheme.pagePadding
            if books.count == 1, let book = books.first {
                card(book, width).frame(width: width).frame(maxHeight: .infinity)
                    .padding(.leading, margin)
            } else if #available(iOS 17, *) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(books) { book in
                            card(book, width).frame(width: width, height: layout.height)
                                .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                    content.scaleEffect(layout.scales && !motion.reducesMotion && !phase.isIdentity ? 0.81 : 1)
                                }
                                .id(book.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, margin, for: .scrollContent)
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: activeSelection, anchor: layout.centered ? .center : .leading)
            } else {
                TabView(selection: activeSelection) {
                    ForEach(books) { book in
                        card(book, width).frame(width: width).tag(Optional(book.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .frame(height: layout.height)
        .accessibilityIdentifier("home.books.carousel")
        .accessibilityScrollAction { edge in
            if edge == .leading { step(-1) }
            if edge == .trailing { step(1) }
        }
    }

    private var activeSelection: Binding<String?> {
        Binding(get: { books.contains { $0.id == selection } ? selection : books.first?.id },
                set: { if let id = $0 { selection = id } })
    }

    private func step(_ direction: Int) {
        let index = (books.firstIndex { $0.id == activeSelection.wrappedValue } ?? 0) + direction
        guard books.indices.contains(index) else { return }
        withAnimation(motion.animation(.navigation)) { activeSelection.wrappedValue = books[index].id }
    }
}
