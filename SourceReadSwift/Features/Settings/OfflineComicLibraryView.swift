import SwiftUI

/// Lists committed image archives, not chapter URL caches or stale job counters.
struct OfflineComicLibraryView: View {
    private struct Edition: Identifiable {
        let record: ChapterDownloadRecord
        let chapters: [BookChapter]
        var id: String { record.id }
    }

    @EnvironmentObject private var appState: AppState
    @State private var editions: [Edition] = []
    @State private var storageBytes: Int64 = 0
    @State private var isLoading = true
    @State private var isClearing = false
    @State private var confirmsClear = false
    @State private var clearError: String?

    private var records: [ChapterDownloadRecord] {
        appState.chapterDownloadStore.records.values.filter { $0.hasComicImageArchive == true }
            .sorted { $0.id < $1.id }
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView("正在检查离线漫画")
            } else if editions.isEmpty {
                Text("暂无离线漫画。在书籍详情下载全本，或在漫画阅读器下载本话。")
                    .foregroundStyle(.secondary)
                Button("刷新离线记录") { Task { await refresh() } }
            } else {
                ForEach(editions) { edition in
                    Section(edition.record.title) {
                        ForEach(edition.chapters) { chapter in
                            NavigationLink {
                                reader(for: chapter, in: edition)
                            } label: {
                                Label(chapter.title, systemImage: "photo.on.rectangle")
                            }
                        }
                    }
                    .listRowBackground(AppThemeRowSurface())
                }
            }
            let active = records.filter { $0.status != .completed }
            if !active.isEmpty {
                Section("下载任务") {
                    ForEach(active) { record in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(record.title).font(.headline)
                            ProgressView(value: record.progress)
                            Text("\(record.completedCount) / \(record.chapterCount) 话 · 失败 \(record.failedCount) 话")
                                .font(.caption).foregroundStyle(.secondary)
                            if appState.chapterDownloadCoordinator.isRunning(bookID: record.id) {
                                Button("停止下载") { appState.chapterDownloadCoordinator.cancel(bookID: record.id) }
                            } else {
                                Text("下载已停止，可在书籍详情重试未完成章节。")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if !records.isEmpty || storageBytes > 0 {
                Section {
                    Button("清除离线漫画", role: .destructive) { confirmsClear = true }
                        .disabled(isClearing)
                } footer: {
                    Text(ByteCountFormatter.string(fromByteCount: storageBytes, countStyle: .file))
                }
            }
        }
        .navigationTitle("离线漫画")
        .task(id: records) { await refresh() }
        .refreshable { await refresh() }
        .confirmationDialog("清除离线漫画？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("清除所有离线漫画", role: .destructive) { Task { await clear() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("停止漫画下载并移除已保存的漫画图片。小说缓存、书架和阅读进度不受影响。")
        }
        .alert("离线漫画未清除", isPresented: Binding(
            get: { clearError != nil }, set: { if !$0 { clearError = nil } }
        )) {
            Button("关闭", role: .cancel) { clearError = nil }
        } message: {
            Text(clearError ?? "")
        }
    }

    private func reader(for chapter: BookChapter, in edition: Edition) -> some View {
        let record = edition.record
        let source = appState.sourceStore.source(for: record.sourceURL) ?? BookSource(
            bookSourceName: "离线漫画", bookSourceUrl: record.sourceURL, bookSourceType: 2
        )
        return ComicReaderView(bookID: record.id, bookTitle: record.title, source: source,
                               initialChapterIndex: chapter.index, chapters: edition.chapters, engine: appState.engine)
    }

    private func refresh() async {
        let snapshot = records
        var next: [Edition] = []
        for record in snapshot {
            let chapters = await ComicOfflineArchive.shared.chapters(sourceURL: record.sourceURL, bookURL: record.bookURL)
            guard !Task.isCancelled else { return }
            if !chapters.isEmpty { next.append(Edition(record: record, chapters: chapters)) }
        }
        let summary = await ComicOfflineArchive.shared.storageSummary()
        guard !Task.isCancelled, records == snapshot else { return }
        editions = next
        storageBytes = summary.bytes
        isLoading = false
    }

    private func clear() async {
        isClearing = true
        defer { isClearing = false }
        appState.chapterDownloadCoordinator.cancelComicDownloads()
        do {
            try await ComicOfflineArchive.shared.removeAll()
            appState.chapterDownloadStore.removeComicRecords()
            await refresh()
        } catch {
            clearError = "无法删除已保存的图片，请重试。"
            NSLog("Offline comic cleanup failed, code=%ld", (error as NSError).code)
        }
    }
}
