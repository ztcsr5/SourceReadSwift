import SwiftUI

/// The same edition carries its paper, jacket and hierarchy into book details.
struct AntigravityDetailHero: View {
    let book: SearchBook
    let theme: AppVisualTheme
    let readerSourceID: String
    let namespace: Namespace.ID
    var readingContext: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 20))
        layout {
            jacket
            metadata
        }
        .padding(theme.usesEditorialPaper ? 0 : 20)
        .padding(.vertical, theme.usesEditorialPaper ? 20 : 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if theme == .hardcoverStudy {
                RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
                    .fill(theme.dynamicColor(light: theme.cardHex, dark: theme.darkCardHex))
            } else if theme == .porcelain {
                AntigravityDetailWash(book: book)
                    .padding(.horizontal, -AppTheme.pagePadding)
                    .padding(.top, -80)
            }
        }
        .overlay(alignment: .bottom) {
            if theme.usesEditorialPaper {
                Rectangle().fill(theme.controlBorder).frame(height: 0.5)
            }
        }
        .accessibilityIdentifier("bookDetail.theme.\(theme.rawValue)")
    }

    private var jacket: some View {
        EditorialBookJacket(height: 156, palette: .resolve(theme: theme), stance: .detail) {
            AsyncBookCover(urlString: book.coverUrl, width: 112, height: 156,
                baseURLString: book.bookUrl, sourceURLString: book.sourceUrl,
                title: book.name, prefersDeskRaster: true, cornerRadius: 3, usesPlainPlaceholder: true)
        }
        .bookHeroSource(readerSourceID, in: namespace)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(book.name)
                .font(theme.titleFont(size: titleSize, weight: .semibold))
                .foregroundStyle(theme.primaryInk)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("bookDetail.title")
            if let author = book.author?.nilIfEmpty {
                Text(author).font(.subheadline).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let readingContext {
                Label(readingContext, systemImage: "bookmark")
                    .font(.caption).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let source = book.sourceUrl.hasPrefix("local://") ? "本地藏书" : book.sourceName.nilIfEmpty
            let edition = [source, book.wordCount?.nilIfEmpty].compactMap { $0 }.joined(separator: " · ")
            if !edition.isEmpty {
                Text(edition).font(.caption).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AntigravityDetailWash: View {
    let book: SearchBook
    @State private var prepared: UIImage?
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var coverURL: URL? {
        CoverURLResolver.url(from: book.coverUrl, base: book.bookUrl, fallbackBase: book.sourceUrl)
    }

    var body: some View {
        GeometryReader { geometry in
            if !reducesTransparency, contrast != .increased, let prepared {
                Image(uiImage: prepared).resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .opacity(0.24)
                    .mask { LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: reducesTransparency || contrast == .increased ? nil : coverURL) {
            prepared = nil
            guard let coverURL, !reducesTransparency, contrast != .increased else { return }
            let image = await CoverGlassBackdropStore.preparedImage(for: coverURL)
            guard !Task.isCancelled else { return }
            prepared = image
        }
    }
}
