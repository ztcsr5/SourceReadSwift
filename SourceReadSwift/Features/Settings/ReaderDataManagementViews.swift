import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BookshelfBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var snapshot: BookshelfBackupSnapshot

    init(snapshot: BookshelfBackupSnapshot) {
        self.snapshot = snapshot
    }

    init(configuration: ReadConfiguration) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshot = try decoder.decode(BookshelfBackupSnapshot.self, from: configuration.file.regularFileContents ?? Data())
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(snapshot))
    }
}

struct ReaderBookmarksView: View {
    @EnvironmentObject private var appState: AppState

    private var sections: [BookmarkSection] {
        appState.bookshelfStore.books.compactMap { book in
            let bookmarks = (book.bookmarks ?? []).sorted { $0.createdAt > $1.createdAt }
            return bookmarks.isEmpty ? nil : BookmarkSection(book: book, bookmarks: bookmarks)
        }
    }

    @State private var selectedQuoteBookmark: (book: BookshelfBook, bookmark: ReaderBookmark)? = nil
    @State private var exportShareURL: IdentifiableURL?
    @State private var exportError: String?

    var body: some View {
        List {
            if sections.isEmpty {
                emptyState(title: "暂无书签", systemImage: "bookmark", message: "阅读时在工具栏加入书签，它们会集中显示在这里。")
            } else {
                ForEach(sections) { section in
                    Section(section.book.title) {
                        ForEach(section.bookmarks) { bookmark in
                            Button {
                                appState.readerNavigation.open(.shelf(section.book, bookmark: bookmark))
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(bookmark.chapterTitle)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(locationText(bookmark))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(AppTheme.accent)
                                    Text(bookmark.snippet.isEmpty ? "无摘录" : bookmark.snippet)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    selectedQuoteBookmark = (section.book, bookmark)
                                } label: {
                                    Label("卡片", systemImage: "quote.bubble.fill")
                                }
                                .tint(AppTheme.accent)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("删除", role: .destructive) {
                                    appState.bookshelfStore.removeBookmark(bookID: section.book.id, bookmarkID: bookmark.id)
                                }
                            }
                            .contextMenu {
                                Button {
                                    selectedQuoteBookmark = (section.book, bookmark)
                                } label: {
                                    Label("生成金句卡片", systemImage: "quote.bubble")
                                }
                                Button("删除书签", role: .destructive) {
                                    appState.bookshelfStore.removeBookmark(bookID: section.book.id, bookmarkID: bookmark.id)
                                }
                            }
                        }
                    }
                    .listRowBackground(AppThemeRowSurface())
                }
            }
        }
        .pageBackground()
        .navigationTitle("书签")
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportAllBookmarks(asMarkdown: true)
                    } label: {
                        Label("导出 Markdown (.md)", systemImage: "doc.richtext")
                    }
                    Button {
                        exportAllBookmarks(asMarkdown: false)
                    } label: {
                        Label("导出纯文本 (.txt)", systemImage: "doc.plaintext")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(sections.isEmpty)
                .accessibilityLabel("导出书签")
            }
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("好", role: .cancel) { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .sheet(item: $exportShareURL) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: Binding(
            get: { selectedQuoteBookmark != nil },
            set: { if !$0 { selectedQuoteBookmark = nil } }
        )) {
            if let pair = selectedQuoteBookmark {
                QuoteCardView(
                    quote: pair.bookmark.snippet.isEmpty ? pair.bookmark.chapterTitle : pair.bookmark.snippet,
                    bookTitle: pair.book.title,
                    author: pair.book.author,
                    chapterTitle: pair.bookmark.chapterTitle
                )
            }
        }
    }

    private func exportAllBookmarks(asMarkdown: Bool) {
        let books = sections.map(\.book)
        let content = asMarkdown
            ? BookmarkExporter.markdownAllBooks(books)
            : BookmarkExporter.plainTextAllBooks(books)
        let ext = asMarkdown ? "md" : "txt"
        do {
            let url = try BookmarkExporter.writeTemporaryExport(
                content: content,
                filename: "纸间阅读-全部书签",
                fileExtension: ext
            )
            exportShareURL = IdentifiableURL(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private struct BookmarkSection: Identifiable {
        let book: BookshelfBook
        let bookmarks: [ReaderBookmark]
        var id: String { book.id }
    }

    private func locationText(_ bookmark: ReaderBookmark) -> String {
        if let paragraph = bookmark.paragraphIndex {
            return "第 \(bookmark.chapterIndex + 1) 章 · 第 \(paragraph + 1) 段 · \(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))"
        }
        return "第 \(bookmark.chapterIndex + 1) 章 · \(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func emptyState(title: String, systemImage: String, message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .listRowBackground(Color.clear)
    }
}

struct OfflineChapterCacheView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var store: ChapterContentCacheStore
    @State private var exportShareURL: IdentifiableURL?
    @State private var exportingEdition: OfflineChapterEdition.Identity?
    @State private var exportError: String?
    @State private var exportTask: Task<Void, Never>?

    var body: some View {
        let sections = OfflineChapterEdition.group(store.entries)
        List {
            if let exportError {
                Section {
                    Label("导出失败：\(exportError)", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                }
            }
            if sections.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("暂无离线章节").font(.headline)
                    Text("在阅读器目录中缓存章节后，可在无网络时继续阅读。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .listRowBackground(Color.clear)
            } else {
                ForEach(sections) { section in
                    let cachedBook = offlineBook(for: section.id)
                    Section {
                        ForEach(section.entries) { entry in
                            Button {
                                appState.readerNavigation.open(.shelf(cachedBook,
                                    chapterIndex: entry.chapterIndex
                                        ?? Int(entry.chapterURL.split(separator: "#").last ?? "") ?? 0))
                            } label: {
                                cacheRow(entry)
                            }
                            .swipeActions {
                                Button("删除", role: .destructive) {
                                    store.remove(key: entry.key)
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(cachedBook.title)
                            Spacer()
                            Button {
                                exportBook(section: section)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text(exportingEdition == section.id ? "正在导出…" : "导出 TXT")
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                            }
                            .disabled(exportingEdition != nil)
                        }
                    } footer: {
                        Text("\(section.entries.count) 章 · \(byteText(section.entries.reduce(0) { $0 + $1.estimatedByteCount }))")
                    }
                    .listRowBackground(AppThemeRowSurface())
                }
            }
        }
        .pageBackground()
        .navigationTitle("离线章节")
        .listStyle(.insetGrouped)
        .sheet(item: $exportShareURL) { item in
            ShareSheet(items: [item.url])
        }
        .onDisappear {
            exportTask?.cancel()
            exportTask = nil
            exportingEdition = nil
        }
    }

    private func exportBook(section: OfflineChapterEdition) {
        guard exportingEdition == nil else { return }
        let matchedBook = offlineBook(for: section.id)
        let chapters = section.entries.enumerated().map { offset, entry in
            ChapterContent(
                chapter: BookChapter(
                    title: entry.title,
                    url: entry.chapterURL,
                    bookUrl: entry.bookURL,
                    index: entry.chapterIndex ?? offset,
                    isVip: false
                ),
                title: entry.title,
                paragraphs: entry.paragraphs,
                nextContentUrl: nil
            )
        }
        exportError = nil
        exportingEdition = section.id
        exportTask = Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try BookExportService().exportBookToPlainText(book: matchedBook, cachedChapters: chapters) }
            }.value
            guard !Task.isCancelled else {
                if case .success(let url) = result { try? FileManager.default.removeItem(at: url) }
                return
            }
            exportingEdition = nil
            exportTask = nil
            switch result {
            case .success(let url):
                exportShareURL = IdentifiableURL(url: url)
                HapticFeedback.success()
            case .failure(let error):
                exportError = error.localizedDescription
            }
        }
    }

    private func offlineBook(for edition: OfflineChapterEdition.Identity) -> BookshelfBook {
        appState.bookshelfStore.books.first { $0.bookURL == edition.bookURL && $0.sourceURL == edition.sourceURL }
            ?? BookshelfBook(searchBook: SearchBook(
                name: edition.bookURL, author: nil, coverUrl: nil, bookUrl: edition.bookURL,
                sourceName: "离线缓存", sourceUrl: edition.sourceURL, mediaKind: .text))
    }

    private func byteText(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }

    private func cacheRow(_ entry: ChapterContentCacheEntry) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.title)
                .font(.headline)
                .lineLimit(1)
            Text("\(entry.paragraphs.count) 段 · \(entry.cachedAt, format: .dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute())")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("点击继续阅读")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
        }
    }
}
