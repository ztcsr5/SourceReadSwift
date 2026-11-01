import SwiftUI

/// Book details opened inside a reader must not recursively construct a new reader.
struct LocalBookMetadataView: View {
    let book: BookshelfBook
    var onSelectChapter: ((Int) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showFullCatalog = false

    private var chapters: [LocalTextChapter] { book.localChapters ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BookDetailHeader(book: book.asSearchBook, format: book.isLocalEPUB ? "本地 EPUB" : "本地 TXT")
                Button { dismiss() } label: {
                    Label("返回阅读", systemImage: "book.fill")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("阅读进度").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(book.readingProgress, format: .percent.precision(.fractionLength(0)))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ProgressView(value: book.readingProgress).tint(AppTheme.accent)
                    Text(book.currentChapterTitle ?? "第 \(book.currentChapterIndex + 1) 章")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }.podcastCard()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("目录").font(.headline)
                        Spacer()
                        Text("\(max(chapters.count, book.totalChapters)) 章")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    ForEach(chapters.prefix(8), id: \.index) { chapter in chapterButton(chapter) }
                    if chapters.count > 8 {
                        Button("查看全部目录") { showFullCatalog = true }
                            .font(.subheadline.weight(.semibold)).tint(AppTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    } else if chapters.isEmpty {
                        Text("当前文件没有独立章节目录").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.podcastCard()
                VStack(alignment: .leading, spacing: 10) {
                    Text("文件信息").font(.headline)
                    LabeledContent("格式", value: book.isLocalEPUB ? "EPUB" : "TXT")
                    LabeledContent("导入时间", value: book.addedAt.formatted(date: .abbreviated, time: .shortened))
                    // Existing local imports stored publisher/language in intro.
                    // Preserve it, but do not label “zh-CN” as a book synopsis.
                    if let metadata = book.intro?.nilIfEmpty {
                        Text(metadata).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.font(.subheadline).podcastCard()
            }
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle("书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .sheet(isPresented: $showFullCatalog) {
            NavigationStack {
                List(chapters, id: \.index) { chapter in chapterButton(chapter).listRowBackground(AppThemeRowSurface()) }
                    .scrollContentBackground(.hidden).pageBackground()
                    .navigationTitle("目录 · \(chapters.count) 章").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showFullCatalog = false } } }
            }
        }
    }

    private func chapterButton(_ chapter: LocalTextChapter) -> some View {
        Button {
            onSelectChapter?(chapter.index)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Text(chapter.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                if chapter.index == book.currentChapterIndex { Image(systemName: "checkmark") }
            }
            .font(.subheadline).frame(minHeight: 38)
            .foregroundStyle(chapter.index == book.currentChapterIndex ? AppTheme.accent : .primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onSelectChapter == nil || chapter.index == book.currentChapterIndex)
    }
}
