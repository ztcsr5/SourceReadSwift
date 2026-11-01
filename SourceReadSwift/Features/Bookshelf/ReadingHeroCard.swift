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

/// A horizontal cover-and-position card; colour never replaces semantic text contrast.
struct ReadingHeroCard: View {
    let book: BookshelfBook
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage("settings.visualTheme") private var visualTheme = AppVisualTheme.classic.rawValue
    @AppStorage("settings.appearanceRevision") private var appearanceRevision = 0
    @State private var coverImage: UIImage?
    @State private var tone: CoverTone?

    var body: some View {
        let _ = visualTheme
        let _ = appearanceRevision
        HStack(alignment: .top, spacing: 12) {
            AsyncBookCover(urlString: book.coverURL, width: 88, height: 128,
                           baseURLString: book.bookURL, sourceURLString: book.sourceURL,
                           onImageLoad: { coverImage = $0 })
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(ReadingHeroStatus.progress(for: book))
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(book.title)
                    .font(.headline).foregroundStyle(.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(book.author.isEmpty ? "作者未记录" : book.author)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                Text(ReadingHeroStatus.chapter(for: book))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if book.hasUpdates {
                    Label("目录有更新", systemImage: "text.badge.plus")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Label(book.lastReadAt == nil ? "开始阅读" : "继续阅读", systemImage: "book.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                AppTheme.card
                LinearGradient(colors: [surfaceTint, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(Color.primary.opacity(contrast == .increased ? 0.32 : 0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .task(id: coverImage.map(ObjectIdentifier.init)) {
            tone = nil
            guard let coverImage else { return }
            let sampled = await CoverToneSampler.shared.tone(for: coverImage)
            guard !Task.isCancelled else { return }
            tone = sampled
        }
    }

    private var surfaceTint: Color {
        guard contrast != .increased else { return .clear }
        guard CoverURLResolver.url(from: book.coverURL, base: book.bookURL, fallbackBase: book.sourceURL) != nil,
              coverImage != nil, let tone else { return AppTheme.accent.opacity(0.04) }
        return Color(red: tone.red, green: tone.green, blue: tone.blue)
            .opacity(colorScheme == .dark ? 0.14 : 0.10)
    }
}
