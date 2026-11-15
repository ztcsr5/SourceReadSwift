import Foundation
import SwiftUI
import UIKit

/// Soft pill color presets for reader text highlights (background fill + optional text ink;
/// underlines and wavy strokes are deliberately excluded by design).
enum ReaderHighlightPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case amber
    case jade
    case sky
    case lavender
    case rose
    case ink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amber: return "暖杏"
        case .jade: return "竹青"
        case .sky: return "天青"
        case .lavender: return "丁香"
        case .rose: return "胭脂"
        case .ink: return "纯墨"
        }
    }

    var fillHexValue: UInt32 {
        switch self {
        case .amber: return 0xF5A623
        case .jade: return 0x2F9E66
        case .sky: return 0x3B82F6
        case .lavender: return 0x8B5CF6
        case .rose: return 0xE11D48
        case .ink: return 0x6B7280
        }
    }

    func foregroundHexValue(isNight: Bool) -> UInt32 {
        switch (self, isNight) {
        case (.amber, false): return 0x7A4100
        case (.amber, true): return 0xFFD27D
        case (.jade, false): return 0x115E3B
        case (.jade, true): return 0x86EFAC
        case (.sky, false): return 0x1D4ED8
        case (.sky, true): return 0x93C5FD
        case (.lavender, false): return 0x5B21B6
        case (.lavender, true): return 0xDDD6FE
        case (.rose, false): return 0x9F1239
        case (.rose, true): return 0xFDA4AF
        case (.ink, false): return 0x1F2937
        case (.ink, true): return 0xF3F4F6
        }
    }

    func backgroundAlpha(isNight: Bool) -> Double {
        switch (self, isNight) {
        case (.ink, false): return 0.14
        case (.ink, true): return 0.28
        case (_, false): return 0.19
        case (_, true): return 0.26
        }
    }

    func swatchColor(isNight: Bool = false) -> Color {
        Color(hex: fillHexValue, opacity: backgroundAlpha(isNight: isNight))
    }

    func swatchTextColor(isNight: Bool = false) -> Color {
        Color(hex: foregroundHexValue(isNight: isNight))
    }
}

enum ReaderHighlightScopeKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case all
    case bookTitle
    case sourceURL

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部书籍"
        case .bookTitle: return "指定书名"
        case .sourceURL: return "指定书源"
        }
    }
}

enum ReaderHighlightRuleError: LocalizedError, Equatable {
    case emptyPattern
    case invalidRegex(String)

    var errorDescription: String? {
        switch self {
        case .emptyPattern:
            return "关键词或正则表达式不能为空"
        case .invalidRegex(let reason):
            return "正则表达式无效：\(reason)"
        }
    }
}

struct ReaderHighlightRule: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var pattern: String
    var isRegex: Bool
    var caseSensitive: Bool
    var enabled: Bool
    var preset: ReaderHighlightPreset
    /// Optional `#RRGGBB` override for pill background. Nil falls back to preset.
    var customBackgroundHex: String?
    /// Optional `#RRGGBB` override for text ink. Nil falls back to preset ink when `usesPresetForeground` is true.
    var customForegroundHex: String?
    var tintForeground: Bool
    var isBold: Bool
    var scopeKind: ReaderHighlightScopeKind
    var scopeKeyword: String

    init(
        id: String = UUID().uuidString,
        name: String,
        pattern: String,
        isRegex: Bool = false,
        caseSensitive: Bool = false,
        enabled: Bool = true,
        preset: ReaderHighlightPreset = .amber,
        customBackgroundHex: String? = nil,
        customForegroundHex: String? = nil,
        tintForeground: Bool = true,
        isBold: Bool = false,
        scopeKind: ReaderHighlightScopeKind = .all,
        scopeKeyword: String = ""
    ) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.isRegex = isRegex
        self.caseSensitive = caseSensitive
        self.enabled = enabled
        self.preset = preset
        self.customBackgroundHex = customBackgroundHex
        self.customForegroundHex = customForegroundHex
        self.tintForeground = tintForeground
        self.isBold = isBold
        self.scopeKind = scopeKind
        self.scopeKeyword = scopeKeyword
    }

    static let builtInTemplates: [ReaderHighlightRule] = [
        ReaderHighlightRule(
            id: "builtin.dialogue",
            name: "人物对话",
            pattern: "(?:「[^」\\n]{1,180}」|“[^”\\n]{1,180}”)",
            isRegex: true,
            caseSensitive: false,
            enabled: false,
            preset: .amber,
            tintForeground: true,
            isBold: false,
            scopeKind: .all
        ),
        ReaderHighlightRule(
            id: "builtin.system-prompt",
            name: "系统面板与提示",
            pattern: "【[^】\\n]{1,120}】",
            isRegex: true,
            caseSensitive: false,
            enabled: false,
            preset: .jade,
            tintForeground: true,
            isBold: true,
            scopeKind: .all
        )
    ]

    func matchesContext(bookTitle: String, sourceURL: String) -> Bool {
        let keyword = scopeKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        switch scopeKind {
        case .all:
            return true
        case .bookTitle:
            guard !keyword.isEmpty else { return true }
            return bookTitle.localizedCaseInsensitiveContains(keyword)
        case .sourceURL:
            guard !keyword.isEmpty else { return true }
            return sourceURL.localizedCaseInsensitiveContains(keyword)
        }
    }

    func resolvedBackgroundHexValue() -> UInt32 {
        Self.parseHexUInt32(customBackgroundHex) ?? preset.fillHexValue
    }

    func resolvedBackgroundAlpha(isNight: Bool) -> Double {
        if customBackgroundHex?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return isNight ? 0.28 : 0.20
        }
        return preset.backgroundAlpha(isNight: isNight)
    }

    func resolvedBackgroundColor(isNight: Bool) -> Color {
        Color(hex: resolvedBackgroundHexValue(), opacity: resolvedBackgroundAlpha(isNight: isNight))
    }

    func resolvedBackgroundUIColor(isNight: Bool) -> UIColor {
        UIColor(hex: resolvedBackgroundHexValue(), alpha: CGFloat(resolvedBackgroundAlpha(isNight: isNight)))
    }

    func resolvedBackgroundCSS(isNight: Bool) -> String {
        Self.rgbaCSS(hex: resolvedBackgroundHexValue(), alpha: resolvedBackgroundAlpha(isNight: isNight))
    }

    func resolvedForegroundHexValue(isNight: Bool) -> UInt32? {
        if let custom = Self.parseHexUInt32(customForegroundHex) {
            return custom
        }
        guard tintForeground else { return nil }
        return preset.foregroundHexValue(isNight: isNight)
    }

    func resolvedForegroundColor(isNight: Bool) -> Color? {
        resolvedForegroundHexValue(isNight: isNight).map { Color(hex: $0) }
    }

    func resolvedForegroundUIColor(isNight: Bool) -> UIColor? {
        resolvedForegroundHexValue(isNight: isNight).map { UIColor(hex: $0) }
    }

    func resolvedForegroundCSS(isNight: Bool) -> String {
        guard let hex = resolvedForegroundHexValue(isNight: isNight) else { return "" }
        return String(format: "#%06X", hex)
    }

    static func parseHexUInt32(_ raw: String?) -> UInt32? {
        guard let raw else { return nil }
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8, let value = UInt32(cleaned, radix: 16) else {
            return nil
        }
        if cleaned.count == 8 {
            return (value >> 8) & 0xFFFFFF
        }
        return value
    }

    private static func rgbaCSS(hex: UInt32, alpha: Double) -> String {
        let r = Int((hex >> 16) & 0xFF)
        let g = Int((hex >> 8) & 0xFF)
        let b = Int(hex & 0xFF)
        return String(format: "rgba(%d,%d,%d,%.3f)", r, g, b, alpha)
    }
}

/// Wire payload serialized to `WebReaderDocument` JS for non-underlined inline pill highlighting.
struct ReaderHighlightRulePayload: Equatable, Sendable {
    let id: String
    let pattern: String
    let isRegex: Bool
    let caseSensitive: Bool
    let backgroundCSS: String
    let foregroundCSS: String
    let isBold: Bool

    var jsonObject: [String: Any] {
        [
            "id": id,
            "pattern": pattern,
            "isRegex": isRegex,
            "caseSensitive": caseSensitive,
            "bg": backgroundCSS,
            "fg": foregroundCSS,
            "bold": isBold
        ]
    }
}

struct ReaderHighlightSpan: Equatable, Sendable {
    let range: NSRange
    let ruleID: String
    let backgroundColor: UIColor
    let foregroundColor: UIColor?
    let isBold: Bool
}

enum ReaderHighlightMatcher {
    private static let maxSpansPerParagraph = 256

    static func activeRules(
        from rules: [ReaderHighlightRule],
        bookTitle: String,
        sourceURL: String
    ) -> [ReaderHighlightRule] {
        rules.filter {
            $0.enabled
                && !$0.pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.matchesContext(bookTitle: bookTitle, sourceURL: sourceURL)
        }
    }

    static func payloads(
        for rules: [ReaderHighlightRule],
        bookTitle: String,
        sourceURL: String,
        isNight: Bool
    ) -> [ReaderHighlightRulePayload] {
        Array(activeRules(from: rules, bookTitle: bookTitle, sourceURL: sourceURL).prefix(64)).map { rule in
            let normalized = normalizedPatternAndSensitivity(pattern: rule.pattern, caseSensitive: rule.caseSensitive)
            return ReaderHighlightRulePayload(
                id: rule.id,
                pattern: rule.isRegex ? normalized.pattern : rule.pattern,
                isRegex: rule.isRegex,
                caseSensitive: normalized.caseSensitive,
                backgroundCSS: rule.resolvedBackgroundCSS(isNight: isNight),
                foregroundCSS: rule.resolvedForegroundCSS(isNight: isNight),
                isBold: rule.isBold
            )
        }
    }

    static func validationError(pattern: String, isRegex: Bool) -> ReaderHighlightRuleError? {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyPattern }
        guard isRegex else { return nil }
        let normalized = normalizedPatternAndSensitivity(pattern: trimmed, caseSensitive: true)
        do {
            _ = try NSRegularExpression(pattern: normalized.pattern, options: normalized.options)
            return nil
        } catch {
            return .invalidRegex(error.localizedDescription)
        }
    }

    /// Computes non-overlapping UTF-16 match spans sorted left-to-right.
    static func matchedSpans(
        in text: String,
        rules: [ReaderHighlightRule],
        isNight: Bool
    ) -> [ReaderHighlightSpan] {
        guard !text.isEmpty, !rules.isEmpty else { return [] }
        let nsText = text as NSString
        let fullLength = nsText.length
        var rawCandidates: [(order: Int, span: ReaderHighlightSpan)] = []

        for (order, rule) in rules.enumerated() where rule.enabled {
            let pattern = rule.pattern
            guard !pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let bg = rule.resolvedBackgroundUIColor(isNight: isNight)
            let fg = rule.resolvedForegroundUIColor(isNight: isNight)

            if rule.isRegex {
                let norm = normalizedPatternAndSensitivity(pattern: pattern, caseSensitive: rule.caseSensitive)
                guard let regex = try? NSRegularExpression(pattern: norm.pattern, options: norm.options) else {
                    continue
                }
                var count = 0
                regex.enumerateMatches(in: text, range: NSRange(location: 0, length: fullLength)) { match, _, stop in
                    guard let range = match?.range,
                          range.location != NSNotFound,
                          range.length > 0 else { return }
                    rawCandidates.append((order, ReaderHighlightSpan(
                        range: range,
                        ruleID: rule.id,
                        backgroundColor: bg,
                        foregroundColor: fg,
                        isBold: rule.isBold
                    )))
                    count += 1
                    if count >= maxSpansPerParagraph {
                        stop.pointee = true
                    }
                }
            } else {
                let options: NSString.CompareOptions = rule.caseSensitive ? [] : [.caseInsensitive]
                var searchLocation = 0
                var count = 0
                while searchLocation < fullLength, count < maxSpansPerParagraph {
                    let searchRange = NSRange(location: searchLocation, length: fullLength - searchLocation)
                    let found = nsText.range(of: pattern, options: options, range: searchRange)
                    guard found.location != NSNotFound, found.length > 0 else { break }
                    rawCandidates.append((order, ReaderHighlightSpan(
                        range: found,
                        ruleID: rule.id,
                        backgroundColor: bg,
                        foregroundColor: fg,
                        isBold: rule.isBold
                    )))
                    searchLocation = found.location + found.length
                    count += 1
                }
            }
        }

        guard !rawCandidates.isEmpty else { return [] }
        rawCandidates.sort { lhs, rhs in
            if lhs.span.range.location != rhs.span.range.location {
                return lhs.span.range.location < rhs.span.range.location
            }
            if lhs.order != rhs.order {
                return lhs.order < rhs.order
            }
            return lhs.span.range.length > rhs.span.range.length
        }

        var accepted: [ReaderHighlightSpan] = []
        var cursorEnd = 0
        for candidate in rawCandidates {
            let range = candidate.span.range
            if range.location >= cursorEnd {
                accepted.append(candidate.span)
                cursorEnd = range.location + range.length
                if accepted.count >= maxSpansPerParagraph { break }
            }
        }
        return accepted
    }

    /// Applies highlight rule background, optional text color, and optional bold weight onto an existing
    /// SwiftUI `AttributedString`. Never adds underline attributes.
    static func applyHighlights(
        to attributed: inout AttributedString,
        sourceText: String,
        rules: [ReaderHighlightRule],
        boldFont: Font,
        isNight: Bool
    ) {
        let spans = matchedSpans(in: sourceText, rules: rules, isNight: isNight)
        guard !spans.isEmpty else { return }
        for span in spans {
            guard let swiftRange = Range(span.range, in: sourceText),
                  let attrStart = AttributedString.Index(swiftRange.lowerBound, within: attributed),
                  let attrEnd = AttributedString.Index(swiftRange.upperBound, within: attributed),
                  attrStart < attrEnd else {
                continue
            }
            attributed[attrStart..<attrEnd].backgroundColor = Color(uiColor: span.backgroundColor)
            if let fg = span.foregroundColor {
                attributed[attrStart..<attrEnd].foregroundColor = Color(uiColor: fg)
            }
            if span.isBold {
                attributed[attrStart..<attrEnd].font = boldFont
            }
        }
    }

    static func uiKitAttributedString(
        for text: String,
        rules: [ReaderHighlightRule],
        baseFont: UIFont,
        boldFont: UIFont,
        baseInk: UIColor,
        paragraphStyle: NSParagraphStyle,
        letterSpacing: Double,
        isNight: Bool
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: baseInk,
                .paragraphStyle: paragraphStyle,
                .kern: min(max(letterSpacing, 0), 10)
            ]
        )
        let spans = matchedSpans(in: text, rules: rules, isNight: isNight)
        for span in spans {
            result.addAttribute(.backgroundColor, value: span.backgroundColor, range: span.range)
            if let fg = span.foregroundColor {
                result.addAttribute(.foregroundColor, value: fg, range: span.range)
            }
            if span.isBold {
                result.addAttribute(.font, value: boldFont, range: span.range)
            }
        }
        return result
    }

    /// Converts common leading PCRE inline flags (such as `(?i)` / `(?m)`) into clean pattern + flags
    /// compatible with both `NSRegularExpression` and WebKit JavaScript `RegExp`.
    static func normalizedPatternAndSensitivity(
        pattern: String,
        caseSensitive: Bool
    ) -> (pattern: String, caseSensitive: Bool, options: NSRegularExpression.Options) {
        var remaining = pattern
        var isSensitive = caseSensitive
        var options: NSRegularExpression.Options = []
        if !caseSensitive {
            options.insert(.caseInsensitive)
        }
        if remaining.hasPrefix("(?") && !remaining.hasPrefix("(?:") && !remaining.hasPrefix("(?=") && !remaining.hasPrefix("(?!") && !remaining.hasPrefix("(?<"),
           let close = remaining.firstIndex(of: ")") {
            let flagSlice = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<close]
            if flagSlice.allSatisfy({ "imsu".contains($0) }) {
                if flagSlice.contains("i") {
                    isSensitive = false
                    options.insert(.caseInsensitive)
                }
                if flagSlice.contains("m") {
                    options.insert(.anchorsMatchLines)
                }
                remaining = String(remaining[remaining.index(after: close)...])
            }
        }
        return (remaining, isSensitive, options)
    }
}

@MainActor
final class ReaderHighlightRuleStore: ObservableObject {
    static let shared = ReaderHighlightRuleStore()

    @Published private(set) var rules: [ReaderHighlightRule] = []
    @Published private(set) var revision: Int = 0
    @Published var lastError: String?

    private let fileURL: URL

    init(
        fileURL: URL = AppStorageDirectory.appStorageURL(fileName: "highlight_rules.json"),
        initialTemplates: [ReaderHighlightRule] = ReaderHighlightRule.builtInTemplates
    ) {
        self.fileURL = fileURL
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([ReaderHighlightRule].self, from: data) {
            self.rules = decoded
        } else {
            self.rules = initialTemplates
        }
    }

    func activeRules(bookTitle: String, sourceURL: String) -> [ReaderHighlightRule] {
        ReaderHighlightMatcher.activeRules(from: rules, bookTitle: bookTitle, sourceURL: sourceURL)
    }

    @discardableResult
    func addOrUpdate(_ rule: ReaderHighlightRule) -> Bool {
        if let err = ReaderHighlightMatcher.validationError(pattern: rule.pattern, isRegex: rule.isRegex) {
            lastError = err.localizedDescription
            return false
        }
        lastError = nil
        var sanitized = rule
        sanitized.name = sanitized.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.name.isEmpty {
            sanitized.name = String(sanitized.pattern.prefix(16))
        }
        if let index = rules.firstIndex(where: { $0.id == sanitized.id }) {
            rules[index] = sanitized
        } else {
            rules.insert(sanitized, at: 0)
        }
        commit()
        return true
    }

    func setEnabled(_ enabled: Bool, ruleID: String) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }),
              rules[index].enabled != enabled else { return }
        rules[index].enabled = enabled
        commit()
    }

    func remove(ruleID: String) {
        let before = rules.count
        rules.removeAll { $0.id == ruleID }
        guard rules.count != before else { return }
        commit()
    }

    func restoreDefaultTemplates() {
        var next = rules
        for template in ReaderHighlightRule.builtInTemplates where !next.contains(where: { $0.id == template.id }) {
            next.append(template)
        }
        rules = next
        commit()
    }

    private func commit() {
        revision &+= 1
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(rules)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            lastError = "保存高亮规则失败：\(error.localizedDescription)"
        }
    }
}
