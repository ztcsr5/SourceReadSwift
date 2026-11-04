import SwiftUI

struct BookDetailHeaderOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// An open book above a shallow paper plane, sharing the desk's physical jacket.
struct BookDetailHero: View {
    let book: SearchBook
    let readerSourceID: String
    let namespace: Namespace.ID
    var readingContext: String? = nil
    @State private var hasArrived = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(AppVisualTheme.selectionKey) private var themeRaw = AppVisualTheme.initialSelection.rawValue
    @AppStorage("settings.appearanceRevision") private var revision = 0
    @AppMotion private var motion

    private var theme: AppVisualTheme { AppVisualTheme(rawValue: themeRaw) ?? .classic }
    private var sourceLabel: String? { book.sourceUrl.hasPrefix("local://") ? "本地藏书" : book.sourceName.nilIfEmpty }
    private var palette: FloatingDeskPalette {
        let _ = revision
        return .resolve(theme: theme)
    }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) { cover; title }
            } else {
                HStack(alignment: .center, spacing: 24) { cover; title }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.ink)
        .background(alignment: .bottom) { paperPlane }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: BookDetailHeaderOffset.self,
                    value: proxy.frame(in: .named("bookDetailScroll")).maxY)
            }
        }
        .onAppear { hasArrived = true }
    }

    private var paperPlane: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return AppTheme.card
            .frame(height: typeSize.isAccessibilitySize ? 120 : 108)
            .clipShape(shape)
            .overlay { shape.strokeBorder(palette.mist.opacity(contrast == .increased ? 0.65 : 0.22), lineWidth: 1) }
            .allowsHitTesting(false)
    }

    private var cover: some View {
        EditorialBookJacket(height: 146, palette: palette, stance: .detail) {
            AsyncBookCover(urlString: book.coverUrl, width: 106, height: 146,
                baseURLString: book.bookUrl, sourceURLString: book.sourceUrl,
                title: book.name)
        }
        .bookHeroSource(readerSourceID, in: namespace)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("纸间 / 书籍档案")
                .font(.caption2.weight(.semibold)).tracking(1.1)
                .foregroundStyle(palette.ink.opacity(0.74))
                .accessibilityHidden(true)
            Text(book.name)
                .font(.system(.title2, design: theme == .classic ? .serif : theme.fontDesign).weight(.semibold))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("bookDetail.title")
            if let author = book.author?.nilIfEmpty {
                Text(author).font(.subheadline).foregroundStyle(palette.ink.opacity(0.78))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let readingContext {
                    Label(readingContext, systemImage: "bookmark")
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                }
                Text([sourceLabel, book.wordCount?.nilIfEmpty].compactMap { $0 }.joined(separator: " · "))
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
            .font(.caption)
            .foregroundStyle(palette.ink.opacity(0.72))
            .offset(y: hasArrived || motion.reducesMotion ? 0 : 7)
            .animation(motion.arrivalAnimation(stage: 1), value: hasArrived)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .offset(y: hasArrived || motion.reducesMotion ? 0 : 4)
        .animation(motion.arrivalAnimation(stage: 0), value: hasArrived)
    }
}
