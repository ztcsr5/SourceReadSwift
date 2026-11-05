import Foundation

@MainActor
final class BookshelfStore: ObservableObject {
    @Published private(set) var books: [BookshelfBook] = []
    @Published private(set) var groups: [BookshelfGroup] = []
    @Published private(set) var lastError: String?

    private let persistence: BookshelfPersistence
    private let groupPersistence: BookshelfGroupPersistence
    private var persistenceBatchDepth = 0
    private var persistenceBatchDirty = false
    private var persistenceRevision = 0
    var onBookRead: ((BookshelfBook) -> Void)?

    init(persistence: BookshelfPersistence = BookshelfPersistence(), groupPersistence: BookshelfGroupPersistence = BookshelfGroupPersistence()) {
        self.persistence = persistence
        self.groupPersistence = groupPersistence
        do {
            books = try persistence.load()
            sortBooksWithPinnedOrder()
            groups = try groupPersistence.load().sorted { $0.sortOrder < $1.sortOrder }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func contains(_ searchBook: SearchBook) -> Bool {
        resolvedIndex(of: searchBook) != nil
    }

    /// Local imports persist a stable `local|<UUID>` id while `SearchBook.id` is
    /// derived as `sourceURL|bookURL`, so the two identifiers never match. The
    /// detail screen is handed the derived `SearchBook`, which used to make
    /// `contains` false and sent every local chapter row through the
    /// `sourceURL|bookURL` fallback id that `book(id:)` cannot resolve.
    private func resolvedIndex(of searchBook: SearchBook) -> Int? {
        if let exact = books.firstIndex(where: { $0.id == searchBook.id }) {
            return exact
        }
        guard searchBook.sourceUrl.hasPrefix("local://") else { return nil }
        return books.firstIndex { $0.bookURL == searchBook.bookUrl }
    }

    /// Resolves the bookshelf record behind a local `SearchBook` (whose `id` is
    /// derived) through the stable `bookURL` every local import stores as its id.
    func localBook(matching bookURL: String) -> BookshelfBook? {
        books.first { $0.bookURL == bookURL || $0.id == bookURL }
    }

    func addOrUpdate(_ searchBook: SearchBook) {
        if let shelfIndex = resolvedIndex(of: searchBook) {
            var item = books[shelfIndex]
            item.title = searchBook.name
            item.author = searchBook.author ?? item.author
            item.coverURL = searchBook.coverUrl
            item.sourceName = searchBook.sourceName
            item.sourceURL = searchBook.sourceUrl
            item.bookURL = searchBook.bookUrl
            item.intro = searchBook.intro
            books[shelfIndex] = item
        } else {
            books.insert(BookshelfBook(searchBook: searchBook), at: 0)
        }
        persist()
    }

    func addLocalTextBook(_ localTextBook: LocalTextBook) {
        books.insert(BookshelfBook(localTextBook: localTextBook), at: 0)
        persist()
    }

    /// 首次启动或空书架时引导填充预置经典读物，提升开箱即用品质并满足 App Store 审核准则
    nonisolated static let welcomeSeedPreferenceKey = "bookshelf.hasSeededOnboardingBook.v1"

    func seedOnboardingBookIfNeeded(force: Bool = false) {
        let hasSeededKey = Self.welcomeSeedPreferenceKey
        if !force && UserDefaults.standard.bool(forKey: hasSeededKey) {
            return
        }
        guard books.isEmpty else { return }
        let welcomeBook = OnboardingClassicBook.makeWelcomeBook()
        let bookshelfBook = BookshelfBook(localTextBook: welcomeBook)
        books.insert(bookshelfBook, at: 0)
        persist()
        UserDefaults.standard.set(true, forKey: hasSeededKey)
    }

    func book(id: String) -> BookshelfBook? {
        books.first { $0.id == id }
    }

    func updateDetails(
        bookID: String,
        latestChapterTitle: String?,
        intro: String?,
        totalChapters: Int,
        coverURL: String? = nil
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        let previous = books[index]
        var updated = previous
        if updated.seenTotalChapters == nil {
            updated.seenTotalChapters = previous.totalChapters > 0
                ? previous.totalChapters
                : totalChapters
        }
        updated.latestChapterTitle = latestChapterTitle
        updated.intro = intro ?? previous.intro
        if let coverURL = coverURL?.trimmingCharacters(in: .whitespacesAndNewlines), !coverURL.isEmpty {
            updated.coverURL = coverURL
        }
        updated.totalChapters = max(totalChapters, previous.totalChapters)
        // Compare only metadata; local books may hold their entire text here.
        guard updated.latestChapterTitle != previous.latestChapterTitle || updated.intro != previous.intro
                || updated.coverURL != previous.coverURL || updated.totalChapters != previous.totalChapters
                || updated.seenTotalChapters != previous.seenTotalChapters else { return }
        books[index] = updated
        persist()
    }

    func markUpdatesSeen(bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        guard books[index].seenTotalChapters != books[index].totalChapters else { return }
        books[index].seenTotalChapters = books[index].totalChapters
        // The reader marks the book opened before clearing its update badge.
        // For a never-read book the legacy sidecar intentionally does not restore.
        if books[index].lastReadAt != nil { persistReadingProgress() }
        else { persist() }
    }

    func markUpdatesSeen(bookIDs: Set<String>) {
        guard !bookIDs.isEmpty else { return }
        var changed = false
        for index in books.indices where bookIDs.contains(books[index].id) {
            let value = books[index].totalChapters
            if books[index].seenTotalChapters != value {
                books[index].seenTotalChapters = value
                changed = true
            }
        }
        if changed { persist() }
    }

    func switchSource(
        bookID: String,
        to searchBook: SearchBook,
        latestChapterTitle: String?,
        intro: String?,
        totalChapters: Int
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].title = searchBook.name
        books[index].author = searchBook.author ?? books[index].author
        books[index].coverURL = searchBook.coverUrl ?? books[index].coverURL
        books[index].sourceName = searchBook.sourceName
        books[index].sourceURL = searchBook.sourceUrl
        books[index].bookURL = searchBook.bookUrl
        books[index].intro = intro ?? searchBook.intro ?? books[index].intro
        books[index].latestChapterTitle = latestChapterTitle
        books[index].totalChapters = max(totalChapters, 0)
        books[index].seenTotalChapters = max(totalChapters, 0)
        books[index].currentChapterIndex = 0
        books[index].currentChapterTitle = nil
        books[index].currentParagraphIndex = nil
        books[index].comicPosition = nil
        books[index].bookmarks = nil
        books[index].lastReadAt = Date()
        moveToFront(index: index)
        persist()
    }

    func markRefreshFailure(bookID: String, message: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].intro = books[index].intro ?? message
        persist()
    }

    func updateReadingProgress(
        bookID: String,
        chapterIndex: Int,
        chapterTitle: String?,
        totalChapters: Int,
        paragraphIndex: Int? = nil,
        comicPosition: ComicReadingPosition? = nil
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        var updated = books[index]
        updated.currentChapterIndex = max(0, chapterIndex)
        updated.currentChapterTitle = chapterTitle
        updated.currentParagraphIndex = paragraphIndex.map { max(0, $0) }
        updated.comicPosition = comicPosition
        updated.totalChapters = max(totalChapters, updated.totalChapters)
        updated.seenTotalChapters = max(
            updated.seenTotalChapters ?? 0,
            updated.currentChapterIndex < Int.max ? updated.currentChapterIndex + 1 : Int.max
        )
        updated.lastReadAt = Date()
        // @Published array element mutation emits per field. Build the complete
        // position locally, then publish exactly one coherent shelf snapshot.
        var nextBooks = books
        nextBooks.remove(at: index)
        nextBooks.insert(updated, at: 0)
        books = nextBooks
        persistReadingProgress()
        onBookRead?(updated)
    }

    func markReaderOpened(bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        var updated = books[index]
        updated.lastOpenedAt = Date()
        updated.lastReadAt = Date()
        var nextBooks = books
        nextBooks.remove(at: index)
        nextBooks.insert(updated, at: 0)
        books = nextBooks
        persistReadingProgress()
        onBookRead?(updated)
    }

    func recordReadingSession(bookID: String, duration: TimeInterval) {
        guard duration > 1,
              let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        var updated = books[index]
        updated.readingSessionCount = (updated.readingSessionCount ?? 0) + 1
        updated.totalReadingSeconds = (updated.totalReadingSeconds ?? 0) + duration
        updated.lastReadAt = Date()
        var nextBooks = books
        nextBooks.remove(at: index)
        let target = updated.isPinned ? 0 : (nextBooks.firstIndex(where: { !$0.isPinned }) ?? nextBooks.count)
        nextBooks.insert(updated, at: target)
        books = nextBooks
        persistInBackground()
        onBookRead?(updated)
    }

    func remove(bookID: String) {
        books.removeAll { $0.id == bookID }
        persist()
    }

    func removeBooks(bookIDs: Set<String>) {
        guard !bookIDs.isEmpty else { return }
        books.removeAll { bookIDs.contains($0.id) }
        persist()
    }

    func createGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !groups.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        groups.append(BookshelfGroup(name: trimmed, sortOrder: groups.count))
        persistGroups()
    }

    func deleteGroup(id: String) {
        guard let deletedName = groups.first(where: { $0.id == id })?.name else { return }
        groups.removeAll { $0.id == id }
        for index in books.indices where books[index].groupName == deletedName {
            books[index].groupName = nil
        }
        normalizeGroupOrder()
        persistGroups()
        persist()
    }

    func moveBooks(bookIDs: Set<String>, toGroupName: String?) {
        let normalized = toGroupName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        for index in books.indices where bookIDs.contains(books[index].id) {
            books[index].groupName = normalized
        }
        persist()
    }

    func isBookmarked(bookID: String, chapterIndex: Int, paragraphIndex: Int? = nil) -> Bool {
        book(id: bookID)?.bookmarks?.contains {
            $0.chapterIndex == chapterIndex && $0.paragraphIndex == paragraphIndex
        } ?? false
    }

    func toggleBookmark(
        bookID: String,
        chapterIndex: Int,
        chapterTitle: String,
        paragraphIndex: Int? = nil,
        snippet: String
    ) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        var bookmarks = books[index].bookmarks ?? []
        if let existingIndex = bookmarks.firstIndex(where: {
            $0.chapterIndex == chapterIndex && $0.paragraphIndex == paragraphIndex
        }) {
            bookmarks.remove(at: existingIndex)
        } else {
            bookmarks.insert(
                ReaderBookmark(
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
                    paragraphIndex: paragraphIndex,
                    snippet: snippet
                ),
                at: 0
            )
        }
        books[index].bookmarks = bookmarks
        persist()
    }

    func removeBookmark(bookID: String, bookmarkID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].bookmarks?.removeAll { $0.id == bookmarkID }
        persist()
    }

    /// Returns a portable snapshot. Cookies, login state and source credentials
    /// live in separate stores and are deliberately excluded.
    func backupSnapshot() -> BookshelfBackupSnapshot {
        BookshelfBackupSnapshot(books: books, groups: groups)
    }

    /// Coalesce a burst of background refresh mutations into one disk write.
    /// Published array updates still reach SwiftUI immediately, but JSON
    /// encoding and file I/O happen once when the batch closes.
    func beginBatchUpdates() {
        persistenceBatchDepth += 1
    }

    func endBatchUpdates() {
        guard persistenceBatchDepth > 0 else { return }
        persistenceBatchDepth -= 1
        guard persistenceBatchDepth == 0, persistenceBatchDirty else { return }
        persistenceBatchDirty = false
        persistNow()
    }

    /// Restores a snapshot atomically. Existing records are replaced so a
    /// restore behaves predictably on a new device; malformed/empty backups are
    /// rejected by the caller before this method is reached.
    @discardableResult
    func restore(_ snapshot: BookshelfBackupSnapshot) -> Bool {
        guard snapshot.schemaVersion == 1 else { return false }
        let normalizedGroups = snapshot.groups
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated()
            .map { offset, group in
                var updated = group
                updated.sortOrder = offset
                return updated
            }
        let validGroupNames = Set(normalizedGroups.map(\.name))
        let normalizedBooks = snapshot.books.map { book in
            var updated = book
            if let groupName = updated.groupName, !validGroupNames.contains(groupName) {
                updated.groupName = nil
            }
            return updated
        }
        let previousBooks = books
        let previousGroups = groups
        persistenceRevision &+= 1
        do {
            // Save both files before publishing the new in-memory state. If
            // the second write fails, put the first file back so a restore
            // cannot leave a half-written bookshelf on disk.
            try groupPersistence.save(normalizedGroups)
            do {
                try persistence.save(normalizedBooks)
            } catch {
                try? groupPersistence.save(previousGroups)
                throw error
            }
            books = normalizedBooks
            groups = normalizedGroups
            lastError = nil
            return true
        } catch {
            // Keep the published state aligned with the still-valid snapshot.
            books = previousBooks
            groups = previousGroups
            lastError = error.localizedDescription
            return false
        }
    }

    var recentBooks: [BookshelfBook] {
        let withReadTime = books
            .filter { $0.lastReadAt != nil }
            .sorted { ($0.lastReadAt ?? .distantPast) > ($1.lastReadAt ?? .distantPast) }
        if withReadTime.count >= 2 || books.isEmpty {
            return withReadTime
        }
        var combined = withReadTime
        let seenIDs = Set(combined.map(\.id))
        for b in books where !seenIDs.contains(b.id) {
            combined.append(b)
        }
        return combined
    }

    var updatedBooks: [BookshelfBook] {
        books.filter(\.hasUpdates)
    }

    func togglePin(bookID: String) {
        guard let index = books.firstIndex(where: { $0.id == bookID }) else { return }
        books[index].isPinned.toggle()
        sortBooksWithPinnedOrder()
        persist()
    }

    private func sortBooksWithPinnedOrder() {
        books.sort { b1, b2 in
            if b1.isPinned != b2.isPinned {
                return b1.isPinned && !b2.isPinned
            }
            let t1 = b1.lastReadAt ?? b1.addedAt
            let t2 = b2.lastReadAt ?? b2.addedAt
            return t1 > t2
        }
    }

    private func moveToFront(index: Int) {
        guard books.indices.contains(index) else { return }
        let item = books.remove(at: index)
        if item.isPinned {
            books.insert(item, at: 0)
        } else {
            let firstUnpinnedIndex = books.firstIndex(where: { !$0.isPinned }) ?? books.count
            books.insert(item, at: firstUnpinnedIndex)
        }
    }

    private func persist() {
        if persistenceBatchDepth > 0 {
            persistenceBatchDirty = true
            return
        }
        persistNow()
    }

    private func persistReadingProgress() {
        if persistenceBatchDepth > 0 {
            persistenceBatchDirty = true
            return
        }
        persistenceRevision &+= 1
        let revision = persistenceRevision
        persistence.saveReadingProgressInBackground(books) { [weak self] result in
            Task { @MainActor [weak self] in self?.completePersistence(result, revision: revision) }
        }
    }

    private func persistInBackground() {
        if persistenceBatchDepth > 0 {
            persistenceBatchDirty = true
            return
        }
        persistenceRevision &+= 1
        let revision = persistenceRevision
        persistence.saveInBackground(books) { [weak self] result in
            Task { @MainActor [weak self] in self?.completePersistence(result, revision: revision) }
        }
    }

    /// Waits without blocking MainActor; used before relinquishing background time.
    func waitForPendingWrites() async { await persistence.waitForPendingWrites() }

    private func completePersistence(_ result: Result<Void, Error>, revision: Int) {
        guard revision == persistenceRevision else {
            if case .failure = result { PerformanceSignpost.event("bookshelf.write", "Superseded background write failed") }
            return
        }
        let message: String?
        switch result {
        case .success: message = nil
        case .failure(let error): message = "保存书架或阅读进度失败：\(error.localizedDescription)"
        }
        if lastError != message { lastError = message }
    }

    private func persistNow() {
        persistenceRevision &+= 1
        do {
            try persistence.save(books)
            if lastError != nil { lastError = nil }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func persistGroups() {
        do { try groupPersistence.save(groups) } catch { lastError = error.localizedDescription }
    }

    private func normalizeGroupOrder() {
        groups = groups.enumerated().map { offset, group in
            var updated = group
            updated.sortOrder = offset
            return updated
        }
    }
}
