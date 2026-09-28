import Foundation

/// Fast, memory-efficient smart chapter divider and indexer for local TXT novel files.
struct LocalTxtSmartDivider {
    enum DividerMode: Equatable {
        case smartChinese  // Standard Chinese web novels (第X章/回/节/卷, 楔子, 序言, 番外)
        case numbered      // Numbered items (1. 2. 001. 一、)
        case western       // Western literature (Chapter, Section, Part, Book)
        case custom(String) // User-supplied regular expression
    }

    var mode: DividerMode = .smartChinese
    var customRegexPattern: String? = nil

    func divide(data: Data, fileName: String) -> LocalTextBook {
        let text = ResponseTextDecoder().decode(data: data, headers: [:])
        return divide(text: text, fileName: fileName)
    }

    func divide(text: String, fileName: String) -> LocalTextBook {
        let title = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent.nilIfEmpty ?? "Local Book"
        let chapters = parseChapters(from: text)
        return LocalTextBook(
            title: title,
            author: "Local",
            chapters: chapters
        )
    }

    private func parseChapters(from text: String) -> [LocalTextChapter] {
        guard !text.isEmpty else {
            return [LocalTextChapter(title: "全文", paragraphs: [], index: 0)]
        }

        var lines: [String] = []
        lines.reserveCapacity(2000)

        // Line-by-line enumeration without allocating gigantic split arrays
        text.enumerateLines { line, _ in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                lines.append(trimmed)
            }
        }

        guard !lines.isEmpty else {
            return [LocalTextChapter(title: "全文", paragraphs: [], index: 0)]
        }

        var chapters: [(title: String, paragraphs: [String])] = []
        var currentTitle = "引子"
        var currentParagraphs: [String] = []
        var currentVolume: String? = nil
        var hasDetectedHeading = false

        for line in lines {
            if isVolumeHeading(line) {
                // If there were pending paragraphs, flush them into previous chapter
                if !currentParagraphs.isEmpty {
                    chapters.append((currentTitle, currentParagraphs))
                    currentParagraphs = []
                }
                currentVolume = line.trimmingCharacters(in: CharacterSet(charactersIn: "# \t　"))
                continue
            }

            if isChapterHeading(line) {
                if !currentParagraphs.isEmpty {
                    chapters.append((currentTitle, currentParagraphs))
                    currentParagraphs = []
                }
                let cleanHeading = line.trimmingCharacters(in: CharacterSet(charactersIn: "# \t　"))
                let headingText = cleanHeading.isEmpty ? line : cleanHeading
                if let vol = currentVolume, !vol.isEmpty, !headingText.hasPrefix(vol) {
                    currentTitle = "\(vol) \(headingText)"
                } else {
                    currentTitle = headingText
                }
                hasDetectedHeading = true
            } else {
                // Standardize paragraph leading indentation
                let formatted = formatParagraph(line)
                currentParagraphs.append(formatted)
            }
        }

        if !currentParagraphs.isEmpty {
            chapters.append((currentTitle, currentParagraphs))
        }

        // Fallback for files without standard chapter headings
        if !hasDetectedHeading || chapters.isEmpty {
            if lines.count > 80 {
                let chunkSize = 60
                var chunked: [LocalTextChapter] = []
                var currentChunk: [String] = []
                var partIndex = 1
                for line in lines {
                    currentChunk.append(formatParagraph(line))
                    if currentChunk.count >= chunkSize {
                        chunked.append(LocalTextChapter(title: "第 \(partIndex) 部分", paragraphs: currentChunk, index: partIndex - 1))
                        currentChunk = []
                        partIndex += 1
                    }
                }
                if !currentChunk.isEmpty {
                    chunked.append(LocalTextChapter(title: "第 \(partIndex) 部分", paragraphs: currentChunk, index: partIndex - 1))
                }
                return chunked
            }
            return [LocalTextChapter(title: "全文", paragraphs: lines.map { formatParagraph($0) }, index: 0)]
        }

        return chapters.enumerated().map { index, item in
            LocalTextChapter(title: item.title, paragraphs: item.paragraphs, index: index)
        }
    }

    private func formatParagraph(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Fast Pre-filtering & Regex Matching

    func isVolumeHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 36, !trimmed.isEmpty else { return false }
        // Volume prefix check
        if trimmed.hasPrefix("第") && (trimmed.contains("卷") || trimmed.contains("部")) {
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            return Self.volumeRegex?.firstMatch(in: trimmed, options: [], range: range) != nil
        }
        if trimmed.hasPrefix("正文卷") || trimmed.hasPrefix("作品相关") {
            return true
        }
        return false
    }

    func isChapterHeading(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 50, !trimmed.isEmpty else { return false }

        // Fast O(1) prefix check: 98% of novel lines start with non-heading characters
        guard let firstChar = trimmed.first else { return false }
        let allowedPrefixes: Set<Character> = [
            "第", "卷", "部", "章", "回", "节", "集", "篇", "话", "話",
            "C", "c", "P", "p", "S", "s", "B", "b", "A", "a",
            "序", "楔", "正", "终", "後", "后", "尾", "番", "引",
            "【", "〔", "〖", "「", "『", "〈", "［", "[", "(", "（", "#",
            "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "零", "〇", "一", "二", "两", "三", "四", "五", "六", "七", "八", "九", "十", "百", "千"
        ]

        guard allowedPrefixes.contains(firstChar) else {
            return false
        }

        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)

        // Custom regex override if provided
        if case .custom(let pattern) = mode,
           let customRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            return customRegex.firstMatch(in: trimmed, options: [], range: range) != nil
        }

        return Self.compiledHeadingRegexes.contains { regex in
            regex.firstMatch(in: trimmed, options: [], range: range) != nil
        }
    }

    private static let volumeRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: #"^[ \t　]{0,4}第[\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+[卷部][ 　].{0,30}$"#, options: [.caseInsensitive])
    }()

    private static let compiledHeadingRegexes: [NSRegularExpression] = {
        let patterns = [
            #"^[ \t　]{0,4}#{1,6}[ \t　]*.{1,40}$"#,
            #"^[ \t　]{0,4}#{0,6}[ \t　]*(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第?\s{0,4}[\d零〇一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?!分)|回(?![合来事去])|场(?![和合比电是])|篇(?!张))).{0,30}$"#,
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
}
