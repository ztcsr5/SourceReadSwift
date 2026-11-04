import Foundation

/// One persisted reading context, never an invented quote or estimated reading time.
enum ReadingDeskContent {
    static func chapterNumber(for book: BookshelfBook) -> String? {
        guard book.lastReadAt != nil, book.totalChapters > 0 else { return nil }
        return String(min(max(book.currentChapterIndex, 0), book.totalChapters - 1) + 1)
    }

    static func contextLine(for book: BookshelfBook) -> String {
        let chapter = book.currentChapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if book.lastReadAt != nil, !chapter.isEmpty { return "上次读到 · " + chapter }
        return introduction(from: book.intro) ?? ReadingHeroStatus.chapter(for: book)
    }

    /// Bounded plain text shared by the desk and the reader's opening cover.
    static func introduction(from raw: String?) -> String? {
        let bounded = String((raw ?? "").prefix(4096))
        let plain = bounded.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
        let introduction = plain.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return introduction.isEmpty ? nil : String(introduction.prefix(120))
    }
}

/// An immutable opening position; later bookshelf publications must not seek
/// the visible reader again. A TOC choice only reuses a cursor in that chapter.
struct ReaderLaunchCursor {
    let chapterIndex: Int
    private let paragraphIndex: Int?

    init(book: BookshelfBook, bookmark: ReaderBookmark?, requestedChapterIndex: Int?) {
        let savedChapter = bookmark?.chapterIndex ?? book.currentChapterIndex
        chapterIndex = max(0, requestedChapterIndex ?? savedChapter)
        let savedParagraph = bookmark != nil ? bookmark?.paragraphIndex : book.currentParagraphIndex
        paragraphIndex = chapterIndex == savedChapter ? savedParagraph : nil
    }

    func paragraph(in chapterIndex: Int) -> Int? {
        self.chapterIndex == chapterIndex ? paragraphIndex : nil
    }

    static func shouldShowTitlePage(for book: BookshelfBook?) -> Bool {
        guard let book else { return true }
        // Imports prefill the first chapter's title, and a failed open may set
        // lastReadAt. Neither is a committed cursor or a reading session.
        return book.currentChapterIndex == 0 && book.currentParagraphIndex == nil
            && (book.readingSessionCount ?? 0) == 0
    }
}
