import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    let readingNote = ReadingNoteCatalog.launchNote
    let sourceStore: SourceStore
    let bookshelfStore: BookshelfStore
    private(set) lazy var purifyRuleStore: PurifyRuleStore = {
        let store = injectedPurifyRuleStore ?? PurifyRuleStore()
        observeDeferredStore(store.objectWillChange)
        return store
    }()
    private(set) lazy var chapterContentCacheStore: ChapterContentCacheStore = {
        hasLoadedChapterContentCache = true
        let store = injectedChapterContentCacheStore
            ?? ChapterContentCacheStore(purifyPreferences: .shared)
        return store
    }()
    private(set) lazy var bookTOCacheStore: BookTOCacheStore = {
        injectedBookTOCacheStore ?? BookTOCacheStore()
    }()
    private(set) lazy var chapterDownloadStore: ChapterDownloadStore = {
        let store = injectedChapterDownloadStore ?? ChapterDownloadStore()
        observeDeferredStore(store.objectWillChange)
        return store
    }()
    private(set) lazy var chapterDownloadCoordinator: ChapterDownloadCoordinator =
        ChapterDownloadCoordinator(store: chapterDownloadStore, comicArchive: comicOfflineArchive)
    let comicOfflineArchive: ComicOfflineArchive
    // RSS and diagnostic archives are not needed to render the first shelf frame.
    private(set) lazy var rssArticleStateStore: RSSArticleStateStore = {
        let store = injectedRSSArticleStateStore ?? RSSArticleStateStore()
        observeDeferredStore(store.objectWillChange)
        return store
    }()
    private(set) lazy var rssFeedCacheStore: RSSFeedCacheStore = {
        hasLoadedRSSFeedCache = true
        let store = injectedRSSFeedCacheStore ?? RSSFeedCacheStore()
        observeDeferredStore(store.objectWillChange)
        return store
    }()
    private(set) lazy var rssArticleContentCacheStore: RSSArticleContentCacheStore = {
        hasLoadedRSSArticleCache = true
        let store = injectedRSSArticleContentCacheStore ?? RSSArticleContentCacheStore()
        observeDeferredStore(store.objectWillChange)
        return store
    }()
    private(set) lazy var sourceHealthStore: SourceHealthStore = {
        let store = injectedSourceHealthStore ?? SourceHealthStore()
        observeDeferredStore(store.objectWillChange)
        return store
    }()
    private(set) lazy var sourceDiagnosticHistoryStore: SourceDiagnosticHistoryStore = {
        let store = injectedSourceDiagnosticHistoryStore ?? SourceDiagnosticHistoryStore()
        observeDeferredStore(store.objectWillChange)
        return store
    }()
    private(set) lazy var sourceCookieStore: SourceCookieStore =
        injectedSourceCookieStore ?? SourceCookieStore()
    // Interface enumeration and engine setup belong to the writing service's first use.
    private(set) lazy var sourceWritingServer: LightweightHTTPServer = {
        LightweightHTTPServer(sourceStore: sourceStore, engine: engine, sourceHealthStore: sourceHealthStore)
    }()
    private(set) lazy var readingHistoryStore: ReadingHistoryStore = {
        let store = injectedReadingHistoryStore ?? ReadingHistoryStore()
        loadedReadingHistoryStore = store
        return store
    }()
    private var loadedReadingHistoryStore: ReadingHistoryStore?
    private var hasLoadedChapterContentCache = false
    private var hasLoadedRSSFeedCache = false
    private var hasLoadedRSSArticleCache = false
    private var pendingSettingsCachePreparation: Task<Void, Never>?
    var hasLoadedReadingHistory: Bool { loadedReadingHistoryStore != nil }
    let discoverViewModel: DiscoverViewModel
    lazy var batchCheckCoordinator: SourceBatchCheckCoordinator = SourceBatchCheckCoordinator()
    lazy var bookshelfChapterRefresh = BookshelfChapterRefreshCoordinator(shelf: bookshelfStore,
        sources: sourceStore, engine: engine)
    private let injectedEngine: SourceEngine?
    private let injectedPurifyRuleStore: PurifyRuleStore?
    private let injectedChapterContentCacheStore: ChapterContentCacheStore?
    private let injectedBookTOCacheStore: BookTOCacheStore?
    private let injectedChapterDownloadStore: ChapterDownloadStore?
    private let injectedSourceHealthStore: SourceHealthStore?
    private let injectedSourceCookieStore: SourceCookieStore?
    private let injectedReadingHistoryStore: ReadingHistoryStore?
    private let injectedRSSArticleStateStore: RSSArticleStateStore?
    private let injectedRSSFeedCacheStore: RSSFeedCacheStore?
    private let injectedRSSArticleContentCacheStore: RSSArticleContentCacheStore?
    private let injectedSourceDiagnosticHistoryStore: SourceDiagnosticHistoryStore?
    private var cancellables: Set<AnyCancellable> = []
    private var hasPendingStoreNotification = false
    private var deferredStoreNotification = false
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
            sourceVariables: .shared,
            browserLoginProvider: { url, title in
                SourceBrowserLoginCoordinator.requestSynchronously(url: url, title: title)
            },
            purifyPreferences: .shared
        )
    }()

    // Diagnostics are a bounded snapshot read when opening their detail page.
    // Publishing every network log invalidated the entire app/reader subtree.
    var diagnostics: [DiagnosticEvent] = []
    @Published private(set) var isSourceLibraryLoading = false
    private var sourceLibraryLoad: Task<Void, Never>?
    @Published var isTabChromeHidden = false
    let readerNavigation = ReaderNavigationRouter()
    @Published var isReaderPresented = false {
        didSet {
            guard oldValue, !isReaderPresented, deferredStoreNotification else { return }
            // This @Published change already invalidates the shelf after the reader leaves.
            deferredStoreNotification = false
        }
    }
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
        self.injectedPurifyRuleStore = purifyRuleStore
        self.injectedChapterContentCacheStore = chapterContentCacheStore
        self.injectedBookTOCacheStore = bookTOCacheStore
        self.injectedChapterDownloadStore = chapterDownloadStore
        self.comicOfflineArchive = comicOfflineArchive
        self.injectedSourceHealthStore = sourceHealthStore
        self.injectedSourceCookieStore = sourceCookieStore
        self.injectedReadingHistoryStore = readingHistoryStore
        self.injectedRSSArticleStateStore = rssArticleStateStore
        self.injectedRSSFeedCacheStore = rssFeedCacheStore
        self.injectedRSSArticleContentCacheStore = rssArticleContentCacheStore
        self.injectedSourceDiagnosticHistoryStore = sourceDiagnosticHistoryStore
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

    /// Makes the real shelf available while the independent source archive is decoding.
    func loadSourcesInBackground(using read: Task<Result<SourceLibrarySnapshot, Error>, Never>) {
        guard sourceLibraryLoad == nil else { return }
        isSourceLibraryLoading = true
        sourceStore.beginLoading()
        sourceLibraryLoad = Task { @MainActor [weak self] in
            let result = await read.value
            let prepared = await Task.detached(priority: .userInitiated) {
                result.map { SourceStore.preparedSnapshot($0) }
            }.value
            guard let self else { return }
            sourceStore.finishLoadingPrepared(prepared)
            isSourceLibraryLoading = false
            sourceLibraryLoad = nil
        }
    }

    func awaitSourcesReady() async {
        await sourceLibraryLoad?.value
    }

    /// Prepares settings summaries without opening large cache archives on MainActor.
    func prepareSettingsCaches() async {
        if let pendingSettingsCachePreparation {
            await pendingSettingsCachePreparation.value
            return
        }
        let request = Task { @MainActor in
            if !hasLoadedChapterContentCache {
                let store = if let injectedChapterContentCacheStore { injectedChapterContentCacheStore }
                    else { await ChapterContentCacheStore.loadInBackground() }
                // A reader may have opened the same lazy store during the disk read.
                if !hasLoadedChapterContentCache {
                    chapterContentCacheStore = store
                    hasLoadedChapterContentCache = true
                }
            }
            if !hasLoadedRSSFeedCache {
                let store = if let injectedRSSFeedCacheStore { injectedRSSFeedCacheStore }
                    else { await RSSFeedCacheStore.loadInBackground() }
                if !hasLoadedRSSFeedCache {
                    rssFeedCacheStore = store
                    hasLoadedRSSFeedCache = true
                    observeDeferredStore(store.objectWillChange)
                }
            }
            if !hasLoadedRSSArticleCache {
                let store = if let injectedRSSArticleContentCacheStore { injectedRSSArticleContentCacheStore }
                    else { await RSSArticleContentCacheStore.loadInBackground() }
                if !hasLoadedRSSArticleCache {
                    rssArticleContentCacheStore = store
                    hasLoadedRSSArticleCache = true
                    observeDeferredStore(store.objectWillChange)
                }
            }
        }
        pendingSettingsCachePreparation = request
        await request.value
        pendingSettingsCachePreparation = nil
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics.insert(event, at: 0)
        if diagnostics.count > 200 {
            diagnostics.removeLast(diagnostics.count - 200)
        }
    }

    /// Saves real reader progress without adding the book to the shelf.
    func recordUnshelvedReading(_ book: BookshelfBook, at position: ReaderPreviewPosition, totalChapters: Int) {
        guard position.bookID == book.id, bookshelfStore.book(id: book.id) == nil else { return }
        var entry = book
        entry.currentChapterIndex = position.chapterIndex
        entry.currentChapterTitle = position.chapterTitle
        entry.currentParagraphIndex = position.paragraphIndex
        entry.comicPosition = position.comicPosition
        entry.totalChapters = totalChapters
        readingHistoryStore.record(book: entry)
    }

    /// Finishes already-enqueued progress/history writes under one finite OS lease.
    func finishReadingWritesInBackground(capturingPosition: () -> Void = {}) {
        let lease = ReadingWriteBackgroundLease()
        capturingPosition()
        let bookshelfStore = bookshelfStore
        let readingHistoryStore = loadedReadingHistoryStore
        Task { @MainActor in
            await bookshelfStore.waitForPendingWrites()
            await readingHistoryStore?.waitForPendingWrites()
            lease.end()
        }
    }

    private func scheduleStoreNotification() {
        guard !isReaderPresented else {
            deferredStoreNotification = true
            return
        }
        guard !hasPendingStoreNotification else { return }
        hasPendingStoreNotification = true
        // Store publishers emit before their mutation. Forward after the current
        // turn so observers read the final state, once for a synchronous burst.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.hasPendingStoreNotification = false
            guard !self.isReaderPresented else {
                self.deferredStoreNotification = true
                return
            }
            self.objectWillChange.send()
        }
    }

    private func observeDeferredStore(_ publisher: ObservableObjectPublisher) {
        publisher.sink { [weak self] _ in self?.scheduleStoreNotification() }
            .store(in: &cancellables)
    }

    func acquireTabChromeHidden(owner: UUID) {
        activeTabChromeOwners.insert(owner)
        if !isTabChromeHidden { isTabChromeHidden = true }
    }

    func releaseTabChromeHidden(owner: UUID? = nil) {
        if let owner { activeTabChromeOwners.remove(owner) }
        else { activeTabChromeOwners.removeAll() }
        let shouldHide = !activeTabChromeOwners.isEmpty
        if isTabChromeHidden != shouldHide { isTabChromeHidden = shouldHide }
    }

    func importSharedDocument(_ url: URL) {
        if isSourceLibraryLoading {
            Task { @MainActor in
                await awaitSourcesReady()
                importSharedDocument(url)
            }
            return
        }
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
        let integerKeys: Set<String> = ["reader.sleepTimerMinutes", ReaderScreenAwakeDuration.defaultsKey, "reader.preloadChapterCount"]
        let boolKeys: Set<String> = ["reader.keepScreenAwake", "reader.textSelectionEnabled", "reader.bodyUnderline"]
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
