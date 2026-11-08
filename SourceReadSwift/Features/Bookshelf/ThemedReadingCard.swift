import SwiftUI

/// Theme compositions change the reading hierarchy while preserving the same entry action.
struct ThemedReadingCard: View {
    let book: BookshelfBook
    let theme: AppVisualTheme
    let heroNamespace: Namespace.ID
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24

    @ViewBuilder var body: some View {
        if theme.isAtelier {
            AtelierReadingCard(book: book, theme: theme, heroNamespace: heroNamespace)
        } else {
            legacyCard
        }
    }

    private var legacyCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("全书进度").font(.caption.weight(.medium))
                Spacer()
                Text(ReadingHeroStatus.progressValue(for: book)).font(.caption.monospacedDigit())
            }
            .foregroundStyle(theme.atelierPalette?.emphasisInk ?? AppTheme.accent)
            .padding(theme.isAtelier ? 12 : 0)
            .background {
                if let palette = theme.atelierPalette {
                    RoundedRectangle(cornerRadius: min(theme.radius, 8)).fill(palette.emphasisFill)
                }
            }

            if theme.homeComposition == .gallery {
                gallery
            } else {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                    : AnyLayout(HStackLayout(alignment: .top, spacing: 20))
                layout {
                    if theme.homeComposition == .index { cover(height: 108) }
                    metadata
                    if theme.homeComposition == .editorial { cover(height: 140) }
                }
            }
            if theme.homeComposition == .editorial {
                Rectangle().fill(AppTheme.accent.opacity(0.35)).frame(height: 1)
                Text(ReadingDeskContent.contextLine(for: book))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
        }
        .padding(theme.homeComposition == .gallery ? 24 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: theme.radius, shadowOpacity: theme.homeComposition == .index ? 0 : 0.05)
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点继续阅读，长按管理书籍")
        .accessibilityIdentifier("bookshelf.composition." + theme.homeComposition.rawValue)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(book.title).font(ReadingDeskTitleTypography.font(size: titleSize))
                .foregroundStyle(.primary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if let author = book.author.nilIfEmpty {
                Text(author).font(.subheadline).foregroundStyle(.secondary)
            }
            if theme.homeComposition != .editorial {
                Text(ReadingHeroStatus.chapter(for: book))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 16) {
            cover(height: 132).frame(maxWidth: .infinity)
            Rectangle().fill(AppTheme.accent.opacity(0.25)).frame(height: 1)
            metadata
        }
    }

    private func cover(height: CGFloat) -> some View {
        ShelfBookCover(book: book, width: height * 2 / 3, height: height)
            .padding(.trailing, 6)
            .bookHeroSource("continue|" + book.id, in: heroNamespace)
    }
}
