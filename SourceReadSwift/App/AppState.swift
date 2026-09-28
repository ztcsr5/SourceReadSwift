import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    let sourceStore: SourceStore
    let bookshelfStore: BookshelfStore
    let purifyRuleStore: PurifyRuleStore
    let chapterContentCacheStore: ChapterContentCacheStore
    let chapterDownloadStore: ChapterDownloadStore
    let chapterDownloadCoordinator: ChapterDownloadCoordinator
    let rssArticleStateStore: RSSArticleStateStore
    let rssFeedCacheStore: RSSFeedCacheStore
    let rssArticleContentCacheStore: RSSArticleContentCacheStore
    let sourceHealthStore: SourceHealthStore
    let sourceDiagnosticHistoryStore: SourceDiagnosticHistoryStore
    let sourceCookieStore: SourceCookieStore
    let sourceWritingServer: LightweightHTTPServer
    let readingHistoryStore: ReadingHistoryStore
    let discoverViewModel: DiscoverViewModel
    lazy var batchCheckCoordinator: SourceBatchCheckCoordinator = SourceBatchCheckCoordinator()
    private let injectedEngine: SourceEngine?
    private var cancellables: Set<AnyCancellable> = []
    lazy var engine: SourceEngine = {
        if let injectedEngine {
            return injectedEngine
        }
        return LegadoSourceEngine(
            cookieStore: sourceCookieStore,
            diagnostics: DiagnosticSink { event in
                Task { @MainActor [weak self] in
                    self?.record(event)
                }
            },
            purifyRules: { [weak self] in
                await MainActor.run { [weak self] in
                    self?.purifyRuleStore.enabledPatterns ?? []
                }
            }
        )
    }()

    @Published var diagnostics: [DiagnosticEvent] = []
    @Published var isTabChromeHidden = false
    private var tabChromeOwner: UUID?

    init(
        sourceStore: SourceStore? = nil,
        bookshelfStore: BookshelfStore? = nil,
        purifyRuleStore: PurifyRuleStore? = nil,
        chapterContentCacheStore: ChapterContentCacheStore? = nil,
        chapterDownloadStore: ChapterDownloadStore? = nil,
        rssArticleStateStore: RSSArticleStateStore? = nil,
        rssFeedCacheStore: RSSFeedCacheStore? = nil,
        rssArticleContentCacheStore: RSSArticleContentCacheStore? = nil,
        sourceHealthStore: SourceHealthStore? = nil,
        sourceDiagnosticHistoryStore: SourceDiagnosticHistoryStore? = nil,
        sourceCookieStore: SourceCookieStore? = nil,
        readingHistoryStore: ReadingHistoryStore? = nil,
        discoverViewModel: DiscoverViewModel? = nil,
        engine: SourceEngine? = nil
    ) {
        self.sourceStore = sourceStore ?? SourceStore()
        let resolvedBookshelfStore = bookshelfStore ?? BookshelfStore()
        self.bookshelfStore = resolvedBookshelfStore
        self.purifyRuleStore = purifyRuleStore ?? PurifyRuleStore()
        self.chapterContentCacheStore = chapterContentCacheStore ?? ChapterContentCacheStore()
        let resolvedChapterDownloadStore = chapterDownloadStore ?? ChapterDownloadStore()
        self.chapterDownloadStore = resolvedChapterDownloadStore
        self.chapterDownloadCoordinator = ChapterDownloadCoordinator(store: resolvedChapterDownloadStore)
        self.rssArticleStateStore = rssArticleStateStore ?? RSSArticleStateStore()
        self.rssFeedCacheStore = rssFeedCacheStore ?? RSSFeedCacheStore()
        self.rssArticleContentCacheStore = rssArticleContentCacheStore ?? RSSArticleContentCacheStore()
        self.sourceHealthStore = sourceHealthStore ?? SourceHealthStore()
        self.sourceDiagnosticHistoryStore = sourceDiagnosticHistoryStore ?? SourceDiagnosticHistoryStore()
        self.sourceCookieStore = sourceCookieStore ?? SourceCookieStore()
        self.sourceWritingServer = LightweightHTTPServer(sourceStore: self.sourceStore)
        let resolvedReadingHistoryStore = readingHistoryStore ?? ReadingHistoryStore()
        self.readingHistoryStore = resolvedReadingHistoryStore
        let resolvedDiscoverViewModel = discoverViewModel ?? DiscoverViewModel()
        self.discoverViewModel = resolvedDiscoverViewModel
        self.injectedEngine = engine
        resolvedBookshelfStore.onBookRead = { [weak self] book in
            self?.readingHistoryStore.record(book: book)
        }
        resolvedDiscoverViewModel.bind(appState: self)
        bindChildStores()
        resolvedBookshelfStore.seedOnboardingBookIfNeeded()
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics.insert(event, at: 0)
        if diagnostics.count > 200 {
            diagnostics.removeLast(diagnostics.count - 200)
        }
    }

    func acquireTabChromeHidden(owner: UUID) {
        tabChromeOwner = owner
        isTabChromeHidden = true
    }

    func releaseTabChromeHidden(owner: UUID? = nil) {
        if let owner, tabChromeOwner != owner { return }
        tabChromeOwner = nil
        isTabChromeHidden = false
    }

    func importSharedDocument(_ url: URL) {
        do {
            let localURL = try PickedDocumentAccess.copiedURL(from: url)
            let ext = localURL.pathExtension.lowercased()
            if ext == "epub" {
                let parsed = try LocalEPUBBookParser().parse(fileURL: localURL)
                bookshelfStore.addLocalTextBook(parsed)
                record(DiagnosticEvent(level: .info, stage: "import", sourceName: parsed.title, message: "已导入 EPUB"))
            } else {
                let data = try Data(contentsOf: localURL)
                if shouldTrySourceImport(fileExtension: ext, data: data) {
                    do {
                        let report = try sourceStore.importJSONData(data)
                        record(DiagnosticEvent(level: .info, stage: "import", message: report.userMessage))
                    } catch where ext != "json" {
                        let parsed = LocalTextBookParser().parse(data: data, fileName: localURL.lastPathComponent)
                        bookshelfStore.addLocalTextBook(parsed)
                        record(DiagnosticEvent(level: .info, stage: "import", sourceName: parsed.title, message: "已导入本地文本"))
                    }
                } else {
                    let parsed = LocalTextBookParser().parse(data: data, fileName: localURL.lastPathComponent)
                    bookshelfStore.addLocalTextBook(parsed)
                    record(DiagnosticEvent(level: .info, stage: "import", sourceName: parsed.title, message: "已导入本地文本"))
                }
            }
        } catch {
            record(DiagnosticEvent(level: .error, stage: "import", message: "文件导入失败：\(error.localizedDescription)", details: ["file": url.lastPathComponent]))
        }
    }

    private func shouldTrySourceImport(fileExtension ext: String, data: Data) -> Bool {
        if ext == "json" { return true }
        guard ["", "txt", "text", "data"].contains(ext) else { return false }
        let text = ResponseTextDecoder()
            .decode(data: data.prefix(128_000), headers: [:])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return text.hasPrefix("{")
            || text.hasPrefix("[")
            || text.contains("bookSourceName")
            || text.contains("bookSourceUrl")
            || text.contains("ruleSearch")
    }

    private func bindChildStores() {
        sourceStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        bookshelfStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        purifyRuleStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        chapterContentCacheStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        chapterDownloadStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        rssArticleStateStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        rssFeedCacheStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        rssArticleContentCacheStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        sourceHealthStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        sourceDiagnosticHistoryStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        readingHistoryStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        discoverViewModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

    }

    // MARK: - Centralized App Data Backup & Restore

    func makeAppDataBackupSnapshot() -> AppDataBackupSnapshot {
        let keys = [
            "reader.fontSize", "reader.lineSpacing", "reader.pagePadding", "reader.letterSpacing",
            "reader.paragraphSpacing", "reader.paragraphIndent", "reader.titleSpacing", "reader.footerHeight",
            "reader.ttsRate", "reader.autoScrollDelay", "reader.sleepTimerMinutes", "reader.background",
            "reader.mode", "reader.tapZones", "reader.keepScreenAwake", "reader.preloadChapterCount",
            "reader.textSelectionEnabled", "settings.themeMode"
        ]
        let defaults = UserDefaults.standard
        let doubleKeys: Set<String> = [
            "reader.fontSize", "reader.lineSpacing", "reader.pagePadding", "reader.letterSpacing",
            "reader.paragraphSpacing", "reader.paragraphIndent", "reader.titleSpacing", "reader.footerHeight",
            "reader.ttsRate", "reader.autoScrollDelay"
        ]
        let integerKeys: Set<String> = ["reader.sleepTimerMinutes", "reader.preloadChapterCount"]
        let boolKeys: Set<String> = ["reader.keepScreenAwake", "reader.textSelectionEnabled"]
        let preferences = Dictionary(uniqueKeysWithValues: keys.compactMap { key -> (String, BackupPreferenceValue)? in
            guard let value = defaults.object(forKey: key) else { return nil }
            if doubleKeys.contains(key) {
                return (key, .double((value as? NSNumber)?.doubleValue ?? (value as? Double) ?? 0))
            }
            if integerKeys.contains(key) {
                return (key, .integer((value as? NSNumber)?.intValue ?? (value as? Int) ?? 0))
            }
            if boolKeys.contains(key) {
                return (key, .bool((value as? NSNumber)?.boolValue ?? (value as? Bool) ?? false))
            }
            if let string = value as? String { return (key, .string(string)) }
            return nil
        })
        return AppDataBackupSnapshot(
            bookshelf: bookshelfStore.backupSnapshot(),
            sources: sourceStore.backupSnapshot(),
            purifyRules: purifyRuleStore.backupSnapshot(),
            rssState: rssArticleStateStore.backupSnapshot(),
            readerPreferences: preferences
        )
    }

    func restoreAppDataBackup(_ snapshot: AppDataBackupSnapshot) throws {
        let previousSnapshot = makeAppDataBackupSnapshot()
        try AppDataBackupRestorer.restore(
            snapshot,
            previous: previousSnapshot,
            restoreBookshelf: { [weak self] in self?.bookshelfStore.restore($0) ?? false },
            restoreSources: { [weak self] in self?.sourceStore.restore($0) ?? false },
            restorePurifyRules: { [weak self] in self?.purifyRuleStore.restore($0) ?? false },
            restoreRSSState: { [weak self] in self?.rssArticleStateStore.restore($0) },
            restorePreferences: { [weak self] in self?.restoreReaderPreferences($0) }
        )
    }

    func restoreReaderPreferences(_ preferences: [String: BackupPreferenceValue]) {
        let defaults = UserDefaults.standard
        for (key, value) in preferences {
            switch value {
            case .string(let val): defaults.set(val, forKey: key)
            case .double(let val): defaults.set(val, forKey: key)
            case .integer(let val): defaults.set(val, forKey: key)
            case .bool(let val): defaults.set(val, forKey: key)
            }
        }
    }
}
