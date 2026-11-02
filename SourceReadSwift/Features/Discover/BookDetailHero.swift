import SwiftUI

struct BookDetailHeaderOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// A small editorial reading room; the system still owns navigation and interactive back.
struct BookDetailHero: View {
    let book: SearchBook
    let readerSourceID: String
    let namespace: Namespace.ID
    @State private var coverImage: UIImage?
    @State private var tone: CoverTone?
    @State private var hasAppeared = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @AppMotion private var motion

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                Image(systemName: "text.book.closed").foregroundStyle(AppTheme.accent)
                Text("纸间 · 书籍档案").font(.caption.weight(.medium)).tracking(2)
                Rectangle().fill(AppTheme.accent.opacity(0.18)).frame(height: 1)
            }.foregroundStyle(.secondary)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 24) { cover; title }
            } else {
                HStack(alignment: .center, spacing: 24) { cover; title }
            }
            HStack(spacing: 8) {
                Text(book.sourceName).lineLimit(2)
                Spacer()
                if let count = book.wordCount?.nilIfEmpty { Text(count).lineLimit(2) }
            }.font(.caption).foregroundStyle(.secondary)
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(AppTheme.accent.opacity(0.16)).frame(height: 1) }
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .background { CoverAtmosphere(tone: tone) }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.cardRadius)
            .strokeBorder(AppTheme.accent.opacity(contrast == .increased ? 0.45 : 0.16), lineWidth: 1))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: BookDetailHeaderOffset.self,
                    value: proxy.frame(in: .named("bookDetailScroll")).maxY)
            }
        }
        .onAppear { withAnimation(motion.animation(.expansion)) { hasAppeared = true } }
        .task(id: coverImage.map(ObjectIdentifier.init)) {
            guard let coverImage else { tone = nil; return }
            let sampled = await CoverToneSampler.shared.tone(for: coverImage)
            guard !Task.isCancelled else { return }
            withAnimation(motion.animation(.background)) { tone = sampled }
        }
    }

    private var cover: some View {
        BookJacket {
            AsyncBookCover(urlString: book.coverUrl, width: 128, height: 184,
                baseURLString: book.bookUrl, sourceURLString: book.sourceUrl,
                onImageLoad: { coverImage = $0 }, title: book.name)
        }
        .bookHeroSource(readerSourceID, in: namespace)
        .accessibilityHidden(true)
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(book.name).font(.title2.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Text(book.author?.nilIfEmpty ?? "作者未知").font(.subheadline).foregroundStyle(.secondary)
            Image(systemName: "bookmark.fill").font(.title3).foregroundStyle(AppTheme.accent.opacity(0.65))
        }.frame(maxWidth: .infinity, alignment: .leading)
            // Reading identity is never gated by an animation or task. System
            // navigation already provides the reveal; delayed frames stay legible.
            .offset(y: hasAppeared || motion.reducesMotion ? 0 : 8)
    }
}
