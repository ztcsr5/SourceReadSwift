import SwiftUI

/// The rail describes persisted chapter progress, never invented progress for an unread book.
enum AtelierReadingProgress {
    static func fraction(for book: BookshelfBook) -> Double? {
        guard book.lastReadAt != nil, book.totalChapters > 0 else { return nil }
        let index = min(max(book.currentChapterIndex, 0), book.totalChapters - 1)
        return (Double(index) + 1) / Double(book.totalChapters)
    }
}

/// Colour belongs to the book's plinth, not repeated decoration over every page and control.
struct AtelierReadingCard: View {
    let book: BookshelfBook
    let theme: AppVisualTheme
    let heroNamespace: Namespace.ID
    @AppStorage(HomeCompositionPreference.storageKey) private var homeCompositionRaw = HomeCompositionPreference.autoRawValue
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 24

    private var effectiveComposition: AppVisualTheme.HomeComposition {
        AppVisualTheme.HomeComposition(rawValue: homeCompositionRaw) ?? theme.homeComposition
    }
    private var isCompact: Bool { effectiveComposition == .index }
    private var coverHeight: CGFloat { isCompact ? 108 : 120 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                if effectiveComposition != .editorial || typeSize.isAccessibilitySize { cover }
                metadata
                if effectiveComposition == .editorial && !typeSize.isAccessibilitySize { cover }
            }
            progress
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.dynamicColor(light: theme.cardHex, dark: theme.darkCardHex),
                    in: RoundedRectangle(cornerRadius: theme.radius, style: .continuous))
        .overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: theme.radius, style: .continuous)
                    .stroke(theme.primaryInk.opacity(0.5), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点继续阅读，长按管理书籍")
        .accessibilityIdentifier("bookshelf.composition." + effectiveComposition.rawValue)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(book.title)
                .font(ReadingDeskTitleTypography.font(size: titleSize))
                .foregroundStyle(theme.primaryInk)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
            if let author = book.author.nilIfEmpty {
                Text(author).font(.subheadline).foregroundStyle(theme.secondaryInk)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
            }
            Text(ReadingHeroStatus.chapter(for: book))
                .font(.caption).foregroundStyle(theme.secondaryInk)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cover: some View {
        ShelfBookCover(book: book, width: coverHeight * 2 / 3, height: coverHeight, theme: theme)
            .bookHeroSource("continue|" + book.id, in: heroNamespace)
            .padding(16)
            .background {
                if let palette = theme.atelierPalette {
                    // The second pigment forms a shelf beneath the jacket; no symbols or gradients.
                    VStack(spacing: 0) {
                        palette.primary
                        palette.secondary.frame(height: 8)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: min(theme.radius, 12), style: .continuous))
                }
            }
            .accessibilityHidden(true)
    }

    private var progress: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ReadingHeroStatus.progress(for: book))
                .font(.caption.monospacedDigit()).foregroundStyle(theme.secondaryInk)
            if let fraction = AtelierReadingProgress.fraction(for: book) {
                ProgressView(value: fraction).tint(AppTheme.accent).accessibilityHidden(true)
            }
        }
    }
}

/// Directory themes separate rows with space and a rule instead of nested raised cards.
struct BookshelfRowSurface: ViewModifier {
    let theme: AppVisualTheme
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if theme.isAtelier {
            content.overlay(alignment: .bottom) {
                Rectangle().fill(theme.primaryInk.opacity(contrast == .increased ? 0.4 : 0.10))
                    .frame(height: 1).allowsHitTesting(false)
            }
        } else {
            // Every visible list row used to install a blurred Core Animation
            // shadow. A lazy list can have a dozen rows on screen, so the
            // shadow pass dominated the 120 Hz scroll budget. The stroke
            // already separates the card from the paper.
            content.glassPanel(cornerRadius: 16, material: .thinMaterial, shadowOpacity: 0)
        }
    }
}
