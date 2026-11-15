import Foundation

/// Identifies an update gate only when it is the entire chapter, not quoted prose.
enum SourceChapterNotice {
    static let updateMessage = "书源需要更新。请打开书源更新或登录入口，更新后重试当前章节。"
    private static let updateText = #"(?:您(?:的)?|当前|當前)?[书書]源版本(?:[过過]低|太低)(?:(?:[请請](?:及[时時]|先)?)?(?:更新[书書]源|升[级級][书書]源))?(?:[点點][击擊](?:登录|登陆|登入|登錄|登陸)(?:进行|進行)?(?:[书書]源更新|更新[书書]源))?"#
    private static let pattern = try! NSRegularExpression(pattern: "^(?:" + updateText + ")+$")
    private static let placeholders: Set<String> = ["❔", "❓", "？", "?", "□", "�", "\u{FFFC}"]

    /// No gallery/image scan is needed for ordinary prose; gates are short.
    static func requiresUpdate(paragraphs: [String], chapterTitle: String) -> Bool {
        guard (1...16).contains(paragraphs.count),
              paragraphs.contains(where: { $0.prefix(96).contains("源版本") }) else { return false }

        let title = normalized(chapterTitle)
        var combined = ""
        for paragraph in paragraphs {
            let line = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if placeholders.contains(line) || isImageParagraph(line) { continue }
            guard line.utf8.count <= 512 else { return false }
            let text = normalized(line)
            if !text.isEmpty, text != title { combined += text }
        }
        guard !combined.isEmpty else { return false }
        return pattern.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)) != nil
    }

    private static func normalized(_ value: String) -> String {
        value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    private static func isImageParagraph(_ value: String) -> Bool {
        value.hasPrefix("[img]") && value.hasSuffix("[/img]")
    }
}
