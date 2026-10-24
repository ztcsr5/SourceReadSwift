import Foundation

enum BookSourceKind: Int, Codable, CaseIterable, Identifiable, Sendable {
    case text = 0
    case audio = 1
    case comic = 2
    case video = 3

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .text: return "小说"
        case .audio: return "听书"
        case .comic: return "漫画"
        case .video: return "视频"
        }
    }

    var badgeText: String {
        switch self {
        case .text: return "文"
        case .audio: return "听"
        case .comic: return "漫"
        case .video: return "视"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "book.closed"
        case .audio: return "headphones"
        case .comic: return "photo.on.rectangle.angled"
        case .video: return "play.tv"
        }
    }
}

struct SearchBook: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(sourceUrl)|\(bookUrl)" }
    let name: String
    let author: String?
    let coverUrl: String?
    let bookUrl: String
    let sourceName: String
    let sourceUrl: String
    let intro: String?
    let kind: String?
    let lastChapter: String?
    /// Legado `ruleSearch.wordCount` – the source-formatted word-count text
    /// (e.g. "12.3万字"). Kept as a string because sources mix units and text.
    let wordCount: String?
    /// Legado `ruleSearch.checkKeyWord` – extracted from each result and used
    /// to discard rows that do not actually contain the searched keyword.
    let checkKeyWord: String?

    init(
        name: String,
        author: String?,
        coverUrl: String?,
        bookUrl: String,
        sourceName: String,
        sourceUrl: String,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        wordCount: String? = nil,
        checkKeyWord: String? = nil
    ) {
        self.name = name
        self.author = author
        self.coverUrl = coverUrl
        self.bookUrl = bookUrl
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.wordCount = wordCount
        self.checkKeyWord = checkKeyWord
    }
}

struct BookDetail: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(sourceUrl)|\(bookUrl)" }
    let name: String
    let author: String?
    let coverUrl: String?
    let bookUrl: String
    let tocUrl: String?
    let sourceName: String
    let sourceUrl: String
    let intro: String?
    let latestChapter: String?
    /// Legado `ruleBookInfo.wordCount` – the source-formatted word-count text.
    let wordCount: String?
    /// Legado `ruleBookInfo.status` – serialization state (连载中 / 已完结 ...).
    let status: String?
    /// Legado `ruleBookInfo.updateTime` – last update time as rendered by the source.
    let updateTime: String?
    /// Legado `ruleBookInfo.kind` – category / tag text from the detail page.
    let kind: String?

    init(
        name: String,
        author: String?,
        coverUrl: String?,
        bookUrl: String,
        tocUrl: String? = nil,
        sourceName: String,
        sourceUrl: String,
        intro: String?,
        latestChapter: String?,
        wordCount: String? = nil,
        status: String? = nil,
        updateTime: String? = nil,
        kind: String? = nil
    ) {
        self.name = name
        self.author = author
        self.coverUrl = coverUrl
        self.bookUrl = bookUrl
        self.tocUrl = tocUrl
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.intro = intro
        self.latestChapter = latestChapter
        self.wordCount = wordCount
        self.status = status
        self.updateTime = updateTime
        self.kind = kind
    }
}

struct BookChapter: Identifiable, Codable, Hashable, Sendable {
    var id: String { "\(bookUrl)|\(url)|\(title)" }
    let title: String
    let url: String
    let bookUrl: String
    let index: Int
    let isVip: Bool
    /// Legado `ruleToc.updateTime` – source-formatted update timestamp.
    let updateTime: String?
    /// Legado `ruleToc.volumeName` – volume/group heading the chapter belongs to.
    let volumeName: String?
    /// Legado `ruleToc.wordCount` – source-formatted chapter length
    /// (e.g. "3200字"). Optional so caches written before v1.0.23 decode.
    let wordCount: String?

    init(
        title: String,
        url: String,
        bookUrl: String,
        index: Int,
        isVip: Bool = false,
        updateTime: String? = nil,
        volumeName: String? = nil,
        wordCount: String? = nil
    ) {
        self.title = title
        self.url = url
        self.bookUrl = bookUrl
        self.index = index
        self.isVip = isVip
        self.updateTime = updateTime
        self.volumeName = volumeName
        self.wordCount = wordCount
    }
}

extension BookChapter {
    /// Returns a copy with a new zero-based index while preserving every
    /// metadata field.  Rebuilding chapters field-by-field previously dropped
    /// `wordCount` (and would silently drop future fields) during pagination
    /// deduplication and reverse-TOC handling.
    func withIndex(_ newIndex: Int) -> BookChapter {
        BookChapter(
            title: title,
            url: url,
            bookUrl: bookUrl,
            index: newIndex,
            isVip: isVip,
            updateTime: updateTime,
            volumeName: volumeName,
            wordCount: wordCount
        )
    }

    /// Returns a copy with a rewritten title (used by `formatJs`), preserving
    /// all other metadata.
    func withTitle(_ newTitle: String) -> BookChapter {
        BookChapter(
            title: newTitle,
            url: url,
            bookUrl: bookUrl,
            index: index,
            isVip: isVip,
            updateTime: updateTime,
            volumeName: volumeName,
            wordCount: wordCount
        )
    }
}

struct ChapterContent: Codable, Hashable, Sendable {
    let chapter: BookChapter
    let title: String
    let paragraphs: [String]
    let nextContentUrl: String?
    let imageStyle: String?
    /// Legado `ruleContent.payAction`：购买操作（JS 片段，或含 `{{js}}`
    /// 段落的 URL 模板）。解析层只负责透传规则，执行由
    /// `SourceEngine.performPayAction` 在同一 JS 上下文内完成。
    let payAction: String?

    init(
        chapter: BookChapter,
        title: String,
        paragraphs: [String],
        nextContentUrl: String? = nil,
        imageStyle: String? = nil,
        payAction: String? = nil
    ) {
        self.chapter = chapter
        self.title = title
        self.paragraphs = paragraphs
        self.nextContentUrl = nextContentUrl
        self.imageStyle = imageStyle
        self.payAction = payAction
    }

    var readerImageStyle: ReaderImageStyle {
        ReaderImageStyle(rule: imageStyle)
    }

    var text: String {
        paragraphs.joined(separator: "\n")
    }
}

struct ReaderBookmark: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let chapterIndex: Int
    let chapterTitle: String
    let paragraphIndex: Int?
    let snippet: String
    let createdAt: Date

    init(
        id: String = UUID().uuidString,
        chapterIndex: Int,
        chapterTitle: String,
        paragraphIndex: Int? = nil,
        snippet: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.paragraphIndex = paragraphIndex
        self.snippet = snippet
        self.createdAt = createdAt
    }
}
