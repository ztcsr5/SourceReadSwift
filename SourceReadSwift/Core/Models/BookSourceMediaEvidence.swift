import Foundation

/// Recognizes conflicting chapter-rule formats without changing imported source JSON.
enum BookSourceMediaEvidence {
    private static let maximumRuleLength = 32_768
    private static let imageRule = try! NSRegularExpression(
        pattern: #"<\s*(?:amp-)?img\b|(?:\btag\.|//|@|^)(?:amp-)?img\b|\.(?:images|imageList|imgList|imageUrls|picList)\b|(?:#|\.)(?:cp_img|comic[-_]?img|manga[-_]?img)\b|\bdata-original\b|\.lazy@html\b"#,
        options: .caseInsensitive
    )
    private static let videoRule = try! NSRegularExpression(
        pattern: #"<\s*video\b|(?:\btag\.|//|@|^)video\b|\.(?:videoUrl|streamUrl|m3u8|mpd|mp4)\b"#,
        options: .caseInsensitive
    )
    private static let textVideoRule = try! NSRegularExpression(
        pattern: #"\bplayer_(?:aaaa|data)\b|\.vod_play_url\b|java\.startBrowser(?:Await)?\s*\([^)]*,\s*['"]视频['"]\s*\)"#,
        options: .caseInsensitive
    )

    /// Returns a correction only when a chapter rule identifies one medium exclusively.
    static func correction(declared: BookSourceKind, rule: String?) -> BookSourceKind? {
        guard declared == .comic || declared == .video || declared == .text, let rule,
              !rule.isEmpty, rule.utf16.count <= maximumRuleLength else { return nil }
        let range = NSRange(rule.startIndex..<rule.endIndex, in: rule)
        let hasImageRule = imageRule.firstMatch(in: rule, range: range) != nil
        let hasVideoRule = videoRule.firstMatch(in: rule, range: range) != nil
        if declared == .video, hasImageRule && !hasVideoRule { return .comic }
        if declared == .comic, hasVideoRule && !hasImageRule { return .video }
        if declared == .text, !hasImageRule, textVideoRule.firstMatch(in: rule, range: range) != nil { return .video }
        return nil
    }
}
