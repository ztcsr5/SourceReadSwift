import SwiftUI

/// Six cover arrangements share the same book-opening action and cover cache.
struct HomeBookDisplay<BookLabel: View>: View {
    let style: HomeBookPresentation
    let books: [BookshelfBook]
    @Binding var selection: String?
    let theme: AppVisualTheme
    let mediaKind: (BookshelfBook) -> BookSourceKind?
    let onOpenBook: (BookshelfBook) -> Void
    @ViewBuilder let bookLabel: (BookshelfBook, CGFloat, CGFloat, Bool) -> BookLabel

    @AppMotion private var motion
    @Environment(\.colorScheme) private var colorScheme
    @State private var coverTones: [String: CoverTone] = [:]
    @State private var coverImages: [String: UIImage] = [:]

    private var activeBook: BookshelfBook? {
        books.first { $0.id == selection } ?? books.first
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            display.frame(minWidth: 240)
            display
        }
        .accessibilityIdentifier("home.bookDisplay." + style.rawValue)
        .id(style)
        .transition(motion.reducesMotion ? .identity : .opacity.combined(with: .scale(scale: 0.985)))
        .animation(motion.animation(.navigation), value: style)
    }

    private var display: some View {
        VStack(alignment: .leading, spacing: 0) {
            if style != .classic { header }
            switch style {
            case .current:
                EmptyView()
            case .showcase:
                VStack(alignment: .leading, spacing: 12) {
                    carousel(widthFraction: 0.76, height: 342, centered: true, scales: true) { book, width in
                        bookLabel(book, width * 0.72, width * 0.96, false)
                    }
                    if let activeBook { metadata(for: activeBook, centered: true) }
                }
                .padding(.top, 26)
            case .journal:
                journalBooks
            case .classic:
                classicBooks
            case .sculptural:
                carousel(widthFraction: 1, height: 226, centered: true) { book, _ in
                    VStack(alignment: .center, spacing: 8) {
                        bookLabel(book, 108, 141, false)
                        metadata(for: book, centered: true, compact: true)
                    }
                }
                pageIndicator
            case .magazine:
                shelf(isSpine: false)
            case .library:
                shelf(isSpine: true)
            }
        }
        .padding(.bottom, 16)
        .background(alignment: .top) {
            if style == .showcase { showcaseBackdrop.ignoresSafeArea(edges: .top) }
        }
        .task(id: style.rawValue + "|" + (activeBook?.id ?? "")) { await sampleCover(of: activeBook) }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch style {
            case .showcase, .journal:
                Text(Date.now, format: .dateTime.weekday(.wide))
                    .font(.caption).foregroundStyle(theme.secondaryInk)
                Text(Date.now, format: .dateTime.month(.defaultDigits).day())
                    .font(.system(.largeTitle, design: style == .journal ? .serif : .default).weight(.heavy))
            case .sculptural:
                Text("今日阅读。")
                    .font(.system(.title2, design: .serif).weight(.heavy))
                Text(Date.now, format: .dateTime.month().day().weekday())
                    .font(.caption).foregroundStyle(theme.secondaryInk)
            case .magazine:
                editionHeading("阅读特刊", eyebrow: "ISSUE · " + Date.now.formatted(.dateTime.month().day()))
                Rectangle().fill(theme.primaryInk).frame(height: 1)
            case .library:
                editionHeading("书房阅览室", eyebrow: "私人馆藏 · ARCHIVE")
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

    private func editionHeading(_ title: String, eyebrow: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow).font(.caption2.weight(.bold)).tracking(1.2)
            Text(title).font(.system(.title, design: .serif).weight(.heavy))
        }
    }

    private var journalBooks: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("继续阅读").padding(.horizontal, AppTheme.pagePadding)
            if let lead = books.first {
                journalCard(lead)
                    .padding(.horizontal, AppTheme.pagePadding)
            }
            if books.count > 1 {
                carousel(Array(books.dropFirst()), widthFraction: 0.73, height: 92, centered: false) { book, width in
                    compactCard(book, width: width, isTinted: false)
                }
            }
        }
        .padding(.top, 28)
    }

    private var classicBooks: some View {
        VStack(alignment: .leading, spacing: 8) {
            heading("继续阅读").padding(.horizontal, AppTheme.pagePadding)
            if !books.isEmpty {
                carousel(widthFraction: 0.73, height: 103, centered: false) { book, width in
                    classicCard(book, width: width)
                }
            }
        }
        .padding(.top, 28)
    }

    private func journalCard(_ book: BookshelfBook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { onOpenBook(book) } label: {
                HStack(alignment: .center, spacing: 12) {
                    bookLabel(book, 75, 114, false)
                    VStack(alignment: .leading, spacing: 5) {
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
                        Text(ReadingHeroStatus.chapter(for: book))
                            .font(.caption2)
                            .foregroundStyle(theme.secondaryInk)
                            .lineLimit(1)
                        Text(ReadingHeroStatus.progressValue(for: book))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 44)

                if resolvedMediaKind(for: book) == .audio {
                    Button { onOpenBook(book) } label: {
                        Label("听书", systemImage: "headphones")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.card)
                .shadow(color: .black.opacity(0.10), radius: 8, y: 4)
        }
        .accessibilityElement(children: .contain)
    }

    private func classicCard(_ book: BookshelfBook, width: CGFloat) -> some View {
        let tint = coverTones[book.id]
        let base = tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? theme.secondaryInk
        return HStack(alignment: .center, spacing: 10) {
            bookLabel(book, 52, 78, false)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(book.author.nilIfEmpty ?? "作者未记录")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                Text(ReadingHeroStatus.chapter(for: book))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: resolvedMediaKind(for: book)?.systemImage ?? BookSourceKind.text.systemImage)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.88))
                .accessibilityLabel(resolvedMediaKind(for: book)?.displayName ?? BookSourceKind.text.displayName)
        }
        .padding(10)
        .frame(width: width, height: 103, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [base, .black.opacity(0.84)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
    }

    private func compactCard(_ book: BookshelfBook, width: CGFloat?, isTinted: Bool, isLead: Bool = false) -> some View {
        let tint = coverTones[book.id]
        let inks = isTinted ? (Color.white, Color.white.opacity(0.82)) : (theme.primaryInk, theme.secondaryInk)
        return HStack(alignment: .center, spacing: 10) {
            bookLabel(book, isLead ? 68 : 48, isLead ? 98 : 72, false)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(book.title).font(.subheadline.weight(.semibold)).foregroundStyle(inks.0).lineLimit(2)
                    mediaIcon(for: book, color: inks.1)
                }
                if let author = book.author.nilIfEmpty {
                    Text(author).font(.caption).foregroundStyle(inks.1).lineLimit(1)
                }
                Text(ReadingHeroStatus.chapter(for: book))
                    .font(.caption2).foregroundStyle(inks.1).lineLimit(1)
                HStack(spacing: 6) {
                    ProgressView(value: book.readingProgress)
                        .tint(inks.0)
                    Text(ReadingHeroStatus.progressValue(for: book))
                        .font(.caption2.monospacedDigit()).foregroundStyle(inks.1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .frame(width: width)
        .background {
            let outline = RoundedRectangle(cornerRadius: isTinted ? 10 : 14)
            if isTinted {
                let base = tint.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? theme.secondaryInk
                outline.fill(LinearGradient(colors: [base, .black], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay { outline.fill(.black.opacity(0.38)) }
            } else {
                outline.fill(AppTheme.card).shadow(color: .black.opacity(0.10), radius: 6, y: 3)
            }
        }
    }

    private func shelf(isSpine: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                heading(isSpine ? "馆藏书架" : "本期在读")
                Spacer()
                Text(isSpine ? "ON SHELF" : "FEATURED")
                    .font(.caption2.weight(.bold)).tracking(1.0).foregroundStyle(theme.secondaryInk)
            }
            .padding(.horizontal, AppTheme.pagePadding)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: isSpine ? 2 : 12) {
                    ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                        // The archive staggers the spines but keeps every book on the same ledge.
                        bookAction(book) {
                            if isSpine {
                                bookLabel(book, 44, 134 + CGFloat(index % 4) * 3, true)
                            } else {
                                VStack(alignment: .leading, spacing: 6) {
                                    bookLabel(book, 112, 144, false)
                                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                                        Text(book.title).font(.caption.weight(.semibold)).lineLimit(1)
                                        mediaIcon(for: book, color: theme.secondaryInk)
                                    }
                                    Text(book.author.nilIfEmpty ?? "作者未记录")
                                        .font(.caption2).foregroundStyle(theme.secondaryInk).lineLimit(1)
                                }
                                .frame(width: 112, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pagePadding)
                .padding(.top, 8)
            }
            .frame(height: 163)
            .accessibilityIdentifier("home.books.horizontalShelf")
        }
        .padding(.top, 34)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [theme.controlBorder, AppTheme.background.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 8).offset(y: 5).allowsHitTesting(false).accessibilityHidden(true)
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.headline.weight(.bold)).foregroundStyle(theme.primaryInk).accessibilityAddTraits(.isHeader)
    }

    private func mediaIcon(for book: BookshelfBook, color: Color) -> some View {
        let kind = resolvedMediaKind(for: book) ?? .text
        return Image(systemName: kind.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .accessibilityLabel(kind.displayName)
    }

    private func metadata(for book: BookshelfBook, centered: Bool, compact: Bool = false) -> some View {
        VStack(alignment: centered ? .center : .leading, spacing: compact ? 3 : 5) {
            Text(book.author.nilIfEmpty ?? "作者未记录")
                .font(.caption).foregroundStyle(theme.secondaryInk).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(book.title)
                    .font(.system(compact ? .subheadline : .headline, weight: .semibold))
                    .foregroundStyle(theme.primaryInk).lineLimit(2)
                mediaIcon(for: book, color: theme.secondaryInk)
            }
            Text(ReadingHeroStatus.chapter(for: book))
                .font(.caption2).foregroundStyle(theme.secondaryInk).lineLimit(1)
            HStack(spacing: 6) {
                ProgressView(value: book.readingProgress)
                    .tint(theme.primaryInk)
                Text(ReadingHeroStatus.progressValue(for: book))
                    .font(.caption2.monospacedDigit()).foregroundStyle(theme.secondaryInk)
            }
            .frame(maxWidth: compact ? 140 : 220)
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .accessibilityElement(children: .combine)
    }

    private func bookAction<Content: View>(_ book: BookshelfBook, @ViewBuilder content: () -> Content) -> some View {
        Button { onOpenBook(book) } label: {
            content().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private var showcaseBackdrop: some View {
        let tone = activeBook.flatMap { coverTones[$0.id] }
        let color = tone.map { Color(red: $0.red, green: $0.green, blue: $0.blue) } ?? AppTheme.card
        let base = color.opacity(colorScheme == .dark ? 0.31 : 0.75)
        return ZStack {
            if let image = activeBook.flatMap({ coverImages[$0.id] }) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 30)
                    .scaleEffect(1.14)
                    .opacity(colorScheme == .dark ? 0.26 : 0.34)
                    .drawingGroup(opaque: false)
            }
            Rectangle().fill(.ultraThinMaterial).opacity(colorScheme == .dark ? 0.58 : 0.72)
            LinearGradient(stops: [.init(color: base, location: 0), .init(color: base.opacity(0.68), location: 0.48),
                                   .init(color: AppTheme.background.opacity(0.92), location: 1)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .animation(motion.animation(.background), value: activeBook?.id)
        .animation(motion.animation(.background), value: tone)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func sampleCover(of book: BookshelfBook?) async {
        guard style == .showcase || style == .classic,
              let book,
              let url = CoverURLResolver.url(from: book.coverURL, base: book.bookURL, fallbackBase: book.sourceURL),
              let image = await RemoteImageLoader.shared.image(for: url, maxPixelSize: 96, reuseCoverBytes: true),
              !Task.isCancelled else { return }
        coverImages[book.id] = image
        guard coverTones[book.id] == nil,
              let tone = await CoverToneSampler.shared.tone(for: image), !Task.isCancelled else { return }
        coverTones[book.id] = tone
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
                .scrollPosition(id: activeSelection, anchor: .leading)
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
