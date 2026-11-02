import SwiftUI

/// Reports only persisted reading state; chapter-count progress is not elapsed reading time.
enum ReadingHeroStatus {
    static func progress(for book: BookshelfBook) -> String {
        guard book.lastReadAt != nil else { return "待开始" }
        guard book.totalChapters > 0 else { return "进度待记录" }
        let index = min(max(book.currentChapterIndex, 0), book.totalChapters - 1)
        let percent = Int((Double(index) + 1) / Double(book.totalChapters) * 100)
        return "章节进度 \(percent)%"
    }

    static func chapter(for book: BookshelfBook) -> String {
        guard book.lastReadAt != nil else { return "从第一页开始" }
        let title = book.currentChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "上次位置待记录" : "上次读到 · \(title)"
    }
}

/// One current book, with a large physical cover and a cached cover-derived surface.
struct ReadingHeroCard: View {
    let book: BookshelfBook
    var heroNamespace: Namespace.ID? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("settings.visualTheme") private var visualTheme = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @AppMotion private var motion
    @State private var coverImage: UIImage?
    @State private var tone: CoverTone?

    private var hasCoverTone: Bool { tone != nil && coverImage != nil }
    private var ink: Color { hasCoverTone ? .white : .primary }

    var body: some View {
        let _ = visualTheme
        let _ = appearanceRevision
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer(minLength: 0)
                cover
                    .rotation3DEffect(.degrees(motion.reducesMotion ? 0 : -4), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
                    .shadow(color: .black.opacity(contrast == .increased ? 0 : 0.28), radius: 16, y: 12)
                Spacer(minLength: 0)
            }.padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 8) {
                Text(ReadingHeroStatus.progress(for: book)).font(.caption.weight(.medium)).foregroundStyle(ink.opacity(0.75))
                Text(book.title).font(.title2.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(book.author.isEmpty ? "作者未记录" : book.author)
                    .font(.subheadline).foregroundStyle(ink.opacity(0.80))
                Text(ReadingHeroStatus.chapter(for: book)).font(.caption).foregroundStyle(ink.opacity(0.80))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if book.hasUpdates { Label("目录有更新", systemImage: "text.badge.plus").font(.caption) }
                HStack {
                    Label(book.lastReadAt == nil ? "开始阅读" : "继续阅读", systemImage: "book.fill")
                        .font(.subheadline.weight(.semibold)).padding(.horizontal, 16).frame(minHeight: 44)
                        .background(ink.opacity(0.14), in: Capsule())
                    Spacer()
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }.padding(.top, 4)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(ink).padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background { CoverAtmosphere(tone: hasCoverTone ? tone : nil) }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
            .stroke(ink.opacity(contrast == .increased ? 0.45 : 0.12), lineWidth: 1).allowsHitTesting(false) }
        .accessibilityElement(children: .combine)
        .task(id: coverImage.map(ObjectIdentifier.init)) {
            guard let coverImage else { tone = nil; return }
            let sampled = await CoverToneSampler.shared.tone(for: coverImage)
            guard !Task.isCancelled else { return }
            tone = sampled
        }
    }

    @ViewBuilder private var cover: some View {
        let image = AsyncBookCover(urlString: book.coverURL, width: 160, height: 224,
                                   baseURLString: book.bookURL, sourceURLString: book.sourceURL,
                                   onImageLoad: { coverImage = $0 }).accessibilityHidden(true)
        if let heroNamespace { image.bookHeroSource("continue|" + book.id, in: heroNamespace) }
        else { image }
    }
}
