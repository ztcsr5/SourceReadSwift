import SwiftUI

/// Metadata opened inside a reader must not recursively construct a new reader.
struct LocalBookMetadataView: View {
    let book: BookshelfBook
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                Text(book.title).font(.title2.bold()).textSelection(.enabled)
                if !book.author.isEmpty { Text(book.author).foregroundStyle(.secondary) }
            }
            Section("本地文件") {
                LabeledContent("来源", value: book.sourceName)
                LabeledContent("章节", value: "\(max(book.localChapters?.count ?? book.totalChapters, 1))")
                LabeledContent("当前章节", value: book.currentChapterTitle ?? "第\(book.currentChapterIndex + 1)章")
                LabeledContent("导入时间", value: book.addedAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let intro = book.intro, !intro.isEmpty {
                Section("简介") { Text(intro).textSelection(.enabled) }
            }
        }
        .navigationTitle("书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
    }
}
