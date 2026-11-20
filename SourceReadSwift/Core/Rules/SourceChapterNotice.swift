import Foundation

/// Identifies source notices only when they are the entire chapter, not quoted prose.
enum SourceChapterNotice {
    static let updateMessage = "书源需要更新。请打开书源更新或登录入口，更新后重试当前章节。"
    private static let updateText = #"(?:您(?:的)?|当前|當前)?[书書]源版本(?:[过過]低|太低)(?:(?:[请請](?:及[时時]|先)?)?(?:更新[书書]源|升[级級][书書]源))?(?:[点點][击擊](?:登录|登陆|登入|登錄|登陸)(?:进行|進行)?(?:[书書]源更新|更新[书書]源))?"#
    private static let pattern = try! NSRegularExpression(pattern: "^(?:" + updateText + ")+$")
    private static let rateLimitText = #"(?:(?:您(?:的)?|[当當]前)?[账帳賬帐][号號户戶](?:因|由于|由於)?)?(?:[访訪][问問]|[请請]求)(?:[过過](?:[于於])?(?:快|[频頻]繁)|太(?:快|[频頻]繁)|[频頻]繁)(?:(?:已(?:被)?|被)?(?:[暂暫][时時]|[临臨][时時])?(?:封禁|封[锁鎖]|限制(?:[访訪][问問])?))?"#
    private static let retryText = #"[请請](?:在|等待)?(?:[0-9一二三四五六七八九十百两兩]+(?:秒[钟鐘]?|分[钟鐘]|小[时時])[后後]?|稍[后後])(?:再)?(?:重[试試]|[试試])"#
    private static let vipText = #"(?:(?:您)?(?:也可以|也可|可以|可|或者|或)?(?:[开開]通|升[级級]|[购購][买買])(?:VIP|[会會][员員])(?:[会會][员員])?(?:(?:可(?:以)?|即可)?(?:解除|免除|取消|避免)(?:[访訪][问問])?(?:限制|封禁))?)?"#
    private static let rateLimitPattern = try! NSRegularExpression(
        pattern: "^" + rateLimitText + retryText + vipText + "$", options: [.caseInsensitive])
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

    static func isReadableContent(paragraphs: [String], chapterTitle: String) -> Bool {
        paragraphs.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            && !requiresUpdate(paragraphs: paragraphs, chapterTitle: chapterTitle)
            && rateLimitMessage(paragraphs: paragraphs, chapterTitle: chapterTitle) == nil
    }

    static func rateLimitMessage(paragraphs: [String], chapterTitle: String) -> String? {
        guard (1...16).contains(paragraphs.count),
              paragraphs.contains(where: {
                  let prefix = $0.prefix(96)
                  return prefix.contains("访问") || prefix.contains("訪問")
                      || prefix.contains("请求") || prefix.contains("請求")
              }) else { return nil }
        let title = normalized(chapterTitle)
        var lines: [String] = []
        for paragraph in paragraphs {
            let line = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
            if placeholders.contains(line) || isImageParagraph(line) { continue }
            guard line.utf8.count <= 512 else { return nil }
            let text = normalized(line)
            if !text.isEmpty, text != title { lines.append(line) }
        }
        let combined = normalized(lines.joined())
        guard !combined.isEmpty, combined.utf8.count <= 1_024,
              rateLimitPattern.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)) != nil
        else { return nil }
        return "源站暂时限制访问。\n" + lines.joined(separator: "\n")
    }

    private static func normalized(_ value: String) -> String {
        value.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map { String($0) }.joined()
    }

    private static func isImageParagraph(_ value: String) -> Bool {
        value.hasPrefix("[img]") && value.hasSuffix("[/img]")
    }
}
