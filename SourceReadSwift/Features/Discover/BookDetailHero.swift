import SwiftUI

struct BookDetailHeaderOffset: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// The cover remains the next navigation source; no second fetch or animated blur.
struct BookDetailHero: View {
    let book: SearchBook
    let readerSourceID: String
    let namespace: Namespace.ID
    @State private var coverImage: UIImage?
    @State private var tone: CoverTone?
    @State private var hasAppeared = false
    @AppMotion private var motion
    private var ink: Color { tone == nil ? .primary : .white }

    var body: some View {
        VStack(spacing: 20) {
            GeometryReader { proxy in
                let collapse: CGFloat = min(max(-proxy.frame(in: .named("bookDetailScroll")).minY / 240, 0), 1)
                AsyncBookCover(urlString: book.coverUrl, width: 144, height: 200,
                           baseURLString: book.bookUrl, sourceURLString: book.sourceUrl,
                           onImageLoad: { coverImage = $0 })
                .bookHeroSource(readerSourceID, in: namespace)
                .shadow(color: .black.opacity(0.24), radius: 16, y: 12)
                .scaleEffect(1 - collapse * 0.10, anchor: .top)
                .opacity(1 - Double(collapse) * 0.25)
            }.frame(width: 144, height: 200)
                .padding(.top, 12).accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(book.name).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(book.author?.nilIfEmpty ?? "作者未知").font(.subheadline).foregroundStyle(ink.opacity(0.80))
                Text(book.sourceName).font(.caption).foregroundStyle(ink.opacity(0.75))
                if let count = book.wordCount?.nilIfEmpty { Text(count).font(.caption) }
            }
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared || motion.reducesMotion ? 0 : 8)
        }
        .foregroundStyle(ink).padding(24).frame(maxWidth: .infinity)
        .background { CoverAtmosphere(tone: tone) }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: BookDetailHeaderOffset.self, value: proxy.frame(in: .named("bookDetailScroll")).maxY)
            }
        }
        .task {
            withAnimation(motion.animation(.expansion)) { hasAppeared = true }
        }
        .task(id: coverImage.map(ObjectIdentifier.init)) {
            guard let coverImage else { tone = nil; return }
            let sampled = await CoverToneSampler.shared.tone(for: coverImage)
            guard !Task.isCancelled else { return }
            tone = sampled
        }
    }
}
