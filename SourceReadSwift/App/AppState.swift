import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    let readingNote = ReadingNoteCatalog.launchNote
    let sourceStore: SourceStore
    let bookshelfStore: BookshelfStore
    let purifyRuleStore: PurifyRuleStore
    let chapterContentCacheStore: ChapterContentCacheStore
    let bookTOCacheStore: BookTOCacheStore
    let chapterDownloadStore: ChapterDownloadStore
    let chapterDownloadCoordinator: ChapterDownloadCoordinator
    let comicOfflineArchive: ComicOfflineArchive
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
    private var hasPendingStoreNotification = false
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
            },
            sourceVariables: .shared
        )
    }()

    // Diagnostics are a bounded snapshot read when opening their detail page.
    // Publishing every network log invalidated the entire app/reader subtree.
    var diagnostics: [DiagnosticEvent] = []
    @Published var isTabChromeHidden = false
    private var activeTabChromeOwners: Set<UUID> = []

    init(
        sourceStore: SourceStore? = nil,
        bookshelfStore: BookshelfStore? = nil,
        purifyRuleStore: PurifyRuleStore? = nil,
        chapterContentCacheStore: ChapterContentCacheStore? = nil,
        bookTOCacheStore: BookTOCacheStore? = nil,
        chapterDownloadStore: ChapterDownloadStore? = nil,
        rssArticleStateStore: RSSArticleStateStore? = nil,
        rssFeedCacheStore: RSSFeedCacheStore? = nil,
        rssArticleContentCacheStore: RSSArticleContentCacheStore? = nil,
        sourceHealthStore: SourceHealthStore? = nil,
        sourceDiagnosticHistoryStore: SourceDiagnosticHistoryStore? = nil,
        sourceCookieStore: SourceCookieStore? = nil,
        readingHistoryStore: ReadingHistoryStore? = nil,
        discoverViewModel: DiscoverViewModel? = nil,
        engine: SourceEngine? = nil,
        comicOfflineArchive: ComicOfflineArchive = .shared
    ) {
        self.sourceStore = sourceStore ?? SourceStore()
        let resolvedBookshelfStore = bookshelfStore ?? BookshelfStore()
        self.bookshelfStore = resolvedBookshelfStore
        self.purifyRuleStore = purifyRuleStore ?? PurifyRuleStore()
        self.chapterContentCacheStore = chapterContentCacheStore ?? ChapterContentCacheStore()
        self.bookTOCacheStore = bookTOCacheStore ?? BookTOCacheStore()
        let resolvedChapterDownloadStore = chapterDownloadStore ?? ChapterDownloadStore()
        self.chapterDownloadStore = resolvedChapterDownloadStore
        self.comicOfflineArchive = comicOfflineArchive
        self.chapterDownloadCoordinator = ChapterDownloadCoordinator(store: resolvedChapterDownloadStore, comicArchive: comicOfflineArchive)
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
        self.sourceWritingServer.bind(engine: self.engine, healthStore: self.sourceHealthStore)
        resolvedBookshelfStore.seedOnboardingBookIfNeeded()
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics.insert(event, at: 0)
        if diagnostics.count > 200 {
            diagnostics.removeLast(diagnostics.count - 200)
        }
    }

    /// Finishes already-enqueued progress/history writes under one finite OS lease.
    func finishReadingWritesInBackground(capturingPosition: () -> Void = {}) {
        let lease = ReadingWriteBackgroundLease()
        capturingPosition()
        let bookshelfStore = bookshelfStore
        let readingHistoryStore = readingHistoryStore
        Task { @MainActor in
            await bookshelfStore.waitForPendingWrites()
            await readingHistoryStore.waitForPendingWrites()
            lease.end()
        }
    }

    private func scheduleStoreNotification() {
        guard !hasPendingStoreNotification else { return }
        hasPendingStoreNotification = true
        // Store publishers emit before their mutation. Forward after the current
        // turn so observers read the final state, once for a synchronous burst.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingStoreNotification = false
            self.objectWillChange.send()
        }
    }

    func acquireTabChromeHidden(owner: UUID) {
        activeTabChromeOwners.insert(owner)
        NavigationTrace.shared.mark("chrome", "acquire \(owner.uuidString.prefix(8)) owners=\(activeTabChromeOwners.count)")
        if !isTabChromeHidden { isTabChromeHidden = true }
    }

    func releaseTabChromeHidden(owner: UUID? = nil) {
        if let owner {
            activeTabChromeOwners.remove(owner)
        } else {
            activeTabChromeOwners.removeAll()
        }
        let shouldHide = !activeTabChromeOwners.isEmpty
        NavigationTrace.shared.mark("chrome",
            "release \(owner.map { String($0.uuidString.prefix(8)) } ?? "all") owners=\(activeTabChromeOwners.count) hidden=\(shouldHide)")
        if isTabChromeHidden != shouldHide { isTabChromeHidden = shouldHide }
    }

    func importSharedDocument(_ url: URL) {
        do {
            let localURL = try PickedDocumentAccess.copiedURL(from: url)
            let ext = localURL.pathExtension.lowercased()
            if ext == "cbz" {
                Task { @MainActor in
                    do {
                        let parsed = try await Task.detached(priority: .userInitiated) {
                            try LocalComicBookParser().parse(fileURL: localURL)
                        }.value
                        bookshelfStore.addLocalTextBook(parsed)
                        record(DiagnosticEvent(level: .info, stage: "import", sourceName: parsed.title,
                            message: "已导入本地漫画，共 \(parsed.paragraphs.count) 页"))
                    } catch {
                        record(DiagnosticEvent(level: .error, stage: "import",
                            message: "漫画导入失败：\(error.localizedDescription)"))
                    }
                }
                return
            }
            // Sniff the container instead of trusting the copied file name: a
            // share-sheet Inbox copy can drop the ".epub" extension, and the
            // TXT branch below would then render a ZIP as one 全文 chapter.
            if LocalEPUBBookParser.looksLikeEPUB(localURL) {
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
        // All child stores are MainActor-isolated; no per-mutation Task is needed.
        sourceStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStoreNotification()
            }
            .store(in: &cancellables)

        // Reading-progress writes land on `bookshelfStore` every 700 ms while
        // the reader is open. Forwarding them here re-evaluated the whole tab
        // tree - including the 7.5k-line reader - in the middle of a scroll.
        // Screens that render shelf state subscribe to the store themselves,
        // so only structural changes need to reach AppState.
        purifyRuleStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStoreNotification()
            }
            .store(in: &cancellables)

        // Prefetch and LRU touches are cache-local; the offline list observes its store directly.
        chapterDownloadStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStoreNotification()
            }
            .store(in: &cancellables)

        rssArticleStateStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStoreNotification()
            }
            .store(in: &cancellables)

        rssFeedCacheStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStoreNotification()
            }
            .store(in: &cancellables)

        rssArticleContentCacheStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStoreNotification()
            }
            .store(in: &cancellables)

        sourceHealthStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStoreNotification()
            }
            .store(in: &cancellables)

        sourceDiagnosticHistoryStore.objectWillChange
            .sink { [weak self] _ in
                self?.scheduleStoreNotification()
            }
            .store(in: &cancellables)

        // ReadingHistoryView observes its store; periodic position writes
        // must not invalidate every screen through the app container.

        // DiscoverView observes this model directly. Forwarding every search
        // progress / keyword update through AppState redrew every app screen.

    }

    // MARK: - Centralized App Data Backup & Restore

    func makeAppDataBackupSnapshot() -> AppDataBackupSnapshot {
        let keys = AppBackupPreferences.keys
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
        do { try AppBackupPreferences.apply(preferences, to: .standard) }
        catch {
            record(DiagnosticEvent(level: .error, stage: "backup.preferences", message: error.localizedDescription))
        }
    }
}
