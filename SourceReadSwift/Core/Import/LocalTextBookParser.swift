import Foundation

struct LocalTextBookParser {
    func parse(data: Data, fileName: String) -> LocalTextBook {
        let text = ResponseTextDecoder().decode(data: data, headers: [:])
        let title = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.nilIfEmpty ?? "Local Book"
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let chapters = splitChapters(lines: lines, fallbackText: text)
        return LocalTextBook(
            title: title,
            author: "Local",
            chapters: chapters
        )
    }

    private func splitChapters(lines: [String], fallbackText: String) -> [LocalTextChapter] {
        guard !lines.isEmpty else {
            return [LocalTextChapter(title: "全文", paragraphs: [fallbackText], index: 0)]
        }

        var chapters: [(title: String, paragraphs: [String])] = []
        var currentTitle = "全文"
        var currentParagraphs: [String] = []
        var hasDetectedHeading = false

        for line in lines {
            if isChapterHeading(line) {
                if !currentParagraphs.isEmpty {
                    chapters.append((currentTitle, currentParagraphs))
                    currentParagraphs = []
                }
                currentTitle = line
                hasDetectedHeading = true
            } else {
                currentParagraphs.append(line)
            }
        }

        if !currentParagraphs.isEmpty {
            chapters.append((currentTitle, currentParagraphs))
        }

        if !hasDetectedHeading || chapters.isEmpty {
            return [LocalTextChapter(title: "全文", paragraphs: lines, index: 0)]
        }

        return chapters.enumerated().map { index, item in
            LocalTextChapter(title: item.title, paragraphs: item.paragraphs, index: index)
        }
    }

    private static let compiledHeadingRegexes: [NSRegularExpression] = {
        let patterns = [
            #"^[ \t　]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第?\s{0,4}[\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?!分)|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,30}$"#,
            #"^[ \t　]{0,4}\d{1,5}[,.， 、_—\-].{1,30}$"#,
            #"^[ \t　]{0,4}[零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[ 、_—\-].{1,30}$"#,
            #"^[ \t　]{0,4}正文[ 　]{1,4}.{0,20}$"#,
            #"^[ \t　]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|ＰＡＲＴ|[Nn][oO]\.|[Ee]pisode|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)\s{0,4}\d{1,4}.{0,30}$"#,
            #"^[ \t　]{0,4}[【〔〖「『〈［\[(（].{1,30}[】〕〗」』〉］\])）].{0,30}$"#,
            #"^[ \t　]{0,4}(?:[☆★✦✧].{1,30}|(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外)[ 　]{0,4}$"#,
            #"^[ \t　]{0,4}(?:(?:内容|文章)?简介|文案|前言|序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|[卷章][\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8})[ 　]{0,4}.{0,30}$"#,
            #"^.{1,20}[(（][\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,8}[)）][ 　\t]{0,4}$"#,
            #"^[ \t　]{0,4}第\s*[\d零〇一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+\s*[章节卷回部集篇话話].{0,30}$"#,
            #"^[Cc]hapter\s+[0-9IVXLCivxlc]+.*$"#
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
    }()

    func isChapterHeading(_ line: String) -> Bool {
        Self.matchesChapterHeading(line)
    }

    static func matchesChapterHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 48, !trimmed.isEmpty else { return false }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return compiledHeadingRegexes.contains { regex in
            regex.firstMatch(in: trimmed, options: [], range: range) != nil
        }
    }
}

struct LocalTextBook: Equatable {
    let title: String
    let author: String
    let chapters: [LocalTextChapter]
    let coverURL: URL?
    let language: String?
    let publisher: String?
    /// EPUB navigation entries in document order. Plain-text imports leave this empty.
    /// Keeping the entries separate from chapters preserves multiple anchors that
    /// point into one XHTML document and makes EPUB3 fragment navigation portable.
    let navigationEntries: [LocalTextNavigationEntry]

    init(
        title: String,
        author: String,
        chapters: [LocalTextChapter],
        coverURL: URL? = nil,
        language: String? = nil,
        publisher: String? = nil,
        navigationEntries: [LocalTextNavigationEntry] = []
    ) {
        self.title = title
        self.author = author
        self.chapters = chapters
        self.coverURL = coverURL
        self.language = language
        self.publisher = publisher
        self.navigationEntries = navigationEntries
    }

    var paragraphs: [String] {
        chapters.flatMap(\.paragraphs)
    }
}

struct LocalTextNavigationEntry: Codable, Hashable, Sendable, Equatable {
    let title: String
    let sourcePath: String
    let fragment: String?
    let chapterIndex: Int?
    /// Best-effort paragraph offset for fragment links inside an XHTML file.
    /// Nil means the target could not be mapped without changing the source text.
    let paragraphIndex: Int?

    init(title: String, sourcePath: String, fragment: String? = nil, chapterIndex: Int? = nil, paragraphIndex: Int? = nil) {
        self.title = title
        self.sourcePath = sourcePath
        self.fragment = fragment
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
    }
}

struct LocalTextChapter: Identifiable, Codable, Hashable, Sendable, Equatable {
    var id: Int { index }
    let title: String
    let paragraphs: [String]
    let index: Int
    /// EPUB package-relative document path. Nil for imported plain text.
    let sourcePath: String?
    /// First navigation anchor targeting this document, when present.
    let navigationFragment: String?

    init(
        title: String,
        paragraphs: [String],
        index: Int,
        sourcePath: String? = nil,
        navigationFragment: String? = nil
    ) {
        self.title = title
        self.paragraphs = paragraphs
        self.index = index
        self.sourcePath = sourcePath
        self.navigationFragment = navigationFragment
    }

    private enum CodingKeys: String, CodingKey {
        case title, paragraphs, index, sourcePath, navigationFragment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        paragraphs = try container.decode([String].self, forKey: .paragraphs)
        index = try container.decode(Int.self, forKey: .index)
        sourcePath = try container.decodeIfPresent(String.self, forKey: .sourcePath)
        navigationFragment = try container.decodeIfPresent(String.self, forKey: .navigationFragment)
    }
}
