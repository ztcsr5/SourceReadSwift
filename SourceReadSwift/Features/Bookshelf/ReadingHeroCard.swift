import SwiftUI

/// Reports only persisted reading state; chapter-count progress is not elapsed reading time.
enum ReadingHeroStatus {
    static func progress(for book: BookshelfBook) -> String {
        let value = progressValue(for: book)
        return book.lastReadAt != nil && book.totalChapters > 0 ? "全书进度 " + value : value
    }

    static func progressValue(for book: BookshelfBook) -> String {
        guard book.lastReadAt != nil else { return "待开始" }
        guard book.totalChapters > 0 else { return "进度待记录" }
        let index = min(max(book.currentChapterIndex, 0), book.totalChapters - 1)
        let percent = Int((Double(index) + 1) / Double(book.totalChapters) * 100)
        return percent == 0 ? "<1%" : "\(percent)%"
    }

    static func chapter(for book: BookshelfBook) -> String {
        guard book.lastReadAt != nil else { return "从第一页开始" }
        let title = book.currentChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return title.isEmpty ? "上次位置待记录" : "上次读到 · \(title)"
    }
}

/// A compact reading desk: one physical book, theme paper and persisted reading state.
struct ReadingHeroCard: View {
    let book: BookshelfBook
    var heroNamespace: Namespace.ID? = nil
    var usesSpatialStyle = true
    var usesFloatingStyle = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var titleSize: CGFloat = 21
    @AppMotion private var motion

    @ViewBuilder var body: some View {
        if usesSpatialStyle && usesFloatingStyle {
            FloatingReadingDesk(book: book, heroNamespace: heroNamespace)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) { cover; description }
            } else {
                HStack(alignment: .center, spacing: 20) { cover; description }
            }

        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .background(AppTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
            .strokeBorder(AppTheme.accent.opacity(0.14), lineWidth: 0.8).allowsHitTesting(false) }
        .contentShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("轻点继续阅读，长按管理书籍")
    }

    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ReadingHeroStatus.progress(for: book)).font(.caption.weight(.medium)).foregroundStyle(AppTheme.accent)
            Text(book.title).font(ReadingDeskTitleTypography.font(size: titleSize))
                .lineLimit(2)
                .accessibilityLabel(book.title)
            Text(book.author.isEmpty ? "作者未记录" : book.author)
                .font(.caption).foregroundStyle(.secondary)
            Text(ReadingHeroStatus.chapter(for: book)).font(.caption).foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            if book.hasUpdates { Label("目录有更新", systemImage: "text.badge.plus").font(.caption) }
        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            .id(book.id)
            .transition(motion.reducesMotion ? .identity : .opacity.combined(with: .offset(y: 6)))
            .animation(motion.arrivalAnimation(stage: 1), value: book.id)
    }

    @ViewBuilder private var cover: some View {
        let image = AsyncBookCover(urlString: book.coverURL, width: usesSpatialStyle ? 104 : 88, height: usesSpatialStyle ? 144 : 128,
                baseURLString: book.bookURL, sourceURLString: book.sourceURL,
                title: book.title)
        let jacket = Group {
            if usesSpatialStyle { BookJacket { image } } else { image }
        }
        .id(book.id)
        .transition(motion.reducesMotion ? .identity : .opacity.combined(with: .scale(scale: 0.96)))
        .animation(motion.animation(.expansion), value: book.id)
        .accessibilityHidden(true)
        if let heroNamespace {
            jacket.bookHeroSource("continue|" + book.id, in: heroNamespace)
        } else {
            jacket
        }
    }
}
