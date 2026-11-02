import SwiftUI

struct ReaderBindingLibraryView: View {
    @StateObject private var store = ReaderBindingStore()
    @State private var title = ""
    @State private var message: String?
    @State private var isWorking = false
    @State private var isLoaded = false
    @State private var deleting: ReaderBindingRecord?
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("把喜欢的阅读方式，装订成册。") .font(.title3.weight(.semibold))
                Text("一并保存字体、纸张与壁纸裁切、章首装饰、页眉页脚、菜单纸面。不包含书籍内容、进度或翻页模式。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("装帧名称（1–32 个字）").font(.caption)
                TextField("例如：夜读山岚", text: $title).textFieldStyle(.roundedBorder)
                    .submitLabel(.done).onSubmit { saveCurrent() }
                Button(action: saveCurrent) {
                    HStack { Image(systemName: "bookmark.fill"); Text(isWorking ? "正在处理…" : "保存当前整套装帧") }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.borderedProminent).disabled(isWorking || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 32)
            }
            if let message { Text(message).font(.caption).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently) }
            if !isLoaded { ProgressView("正在读取已存装帧") }
            else if store.records.isEmpty {
                Label("尚未保存装帧。先调整上方书页，再为它取个名字。", systemImage: "books.vertical")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(store.records) { record in
                HStack(spacing: 12) {
                    Button {
                        run { try await store.apply(record); message = "已应用「\(record.title)」，阅读位置未改变。"; HapticFeedback.success() }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.title).font(.headline)
                            Text(summary(record)).font(.caption).foregroundStyle(.secondary)
                            Label("应用整套装帧", systemImage: "arrow.up.right").font(.caption)
                        }.frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    }.buttonStyle(AppPressStyle()).disabled(isWorking)
                    Button { deleting = record } label: { Image(systemName: "trash").frame(width: 44, height: 44) }
                        .accessibilityLabel("删除装帧「\(record.title)」").disabled(isWorking)
                }.padding(16).background(AppTheme.elevatedCard, in: RoundedRectangle(cornerRadius: 16))
            }
            Button("重新读取装帧") { reload() }.font(.caption).disabled(isWorking)
        }.task { reload() }
            .confirmationDialog("删除已保存的装帧？不会删除书籍或当前字体。", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                if let deleting { Button("删除「\(deleting.title)」", role: .destructive) { run { try await store.delete(deleting.id); self.deleting = nil; message = "已删除装帧。" } } }
            }.tint(AppTheme.accent)
    }
    private func summary(_ record: ReaderBindingRecord) -> String {
        let paper = ReaderBackground(rawValue: record.preferences.text("reader.background"))?.title ?? "阅读纸面"
        let decoration = ReaderChapterDecoration(rawValue: record.preferences.text("reader.chapterDecoration"))?.title ?? "素笺"
        return paper + " · " + decoration
    }
    private func saveCurrent() {
        guard !isWorking, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 32 else { return }
        run { try await store.save(title: title); message = "已保存「\(title)」。字体、纸张、章首与菜单已一起收好。"; title = ""; HapticFeedback.success() }
    }
    private func reload() { run { try await store.reload(); isLoaded = true } }
    private func run(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isWorking else { return }; isWorking = true
        Task { @MainActor in
            defer { isWorking = false; isLoaded = true }
            do { try await action() } catch { message = "操作未完成：" + error.localizedDescription }
        }
    }
}
