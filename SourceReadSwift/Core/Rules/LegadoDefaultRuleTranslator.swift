import Foundation
import SwiftSoup

struct LegadoRuleStep: Equatable {
    let selector: String
    let index: Int?
    let excludeIndex: Int?
}

struct LegadoTranslatedValueRule: Equatable {
    let steps: [LegadoRuleStep]
    let attribute: String
    let regexTransforms: [String]
}

enum LegadoDefaultRuleTranslator {
    private static let knownAttributes: Set<String> = [
        "text", "text()", "textnodes", "owntext", "owntext()",
        "html", "html()", "all",
        "href", "src", "content", "title", "alt", "value",
        "action", "placeholder", "data-src", "data-original", "data-url"
    ]

    static func isAttributeToken(_ token: String) -> Bool {
        let lower = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if knownAttributes.contains(lower) { return true }
        if lower.hasPrefix("attr(") && lower.hasSuffix(")") { return true }
        if lower.hasPrefix("@attr:") || lower.hasPrefix("@") { return true }
        if lower.hasPrefix("data-") { return true }
        return false
    }

    static func normalizeAttributeName(_ attr: String) -> String {
        var clean = attr.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("@attr:") {
            clean = String(clean.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if clean.hasPrefix("@") {
            clean = String(clean.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clean
    }

    /// Translates a Legado rule (value extraction) into executable steps and attribute.
    /// Supports:
    /// - `class.title@text`
    /// - `id.chapterlist@tag.dd@tag.a@href`
    /// - `tag.p.0@text##regex##replacement`
    /// - `div.box@tag.a@src`
    /// - `class.content@textNodes`
    static func translateValueRule(_ rawRule: String) -> LegadoTranslatedValueRule? {
        var working = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        // Strip @css: or css: prefix if present
        let lower = working.lowercased()
        if lower.hasPrefix("@css:") {
            working = String(working.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("css:") {
            working = String(working.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Split trailing regex transforms: `##pattern##replacement`
        let regexParts = working.components(separatedBy: "##")
        let baseRule = regexParts.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? working
        let transforms = Array(regexParts.dropFirst())

        guard !baseRule.isEmpty else { return nil }

        let rawSegments = baseRule.components(separatedBy: "@")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !rawSegments.isEmpty else { return nil }

        let lastSegment = rawSegments.last!
        let hasAttributeAtEnd = isAttributeToken(lastSegment) || (!isSelectorToken(lastSegment) && rawSegments.count > 1)

        let selectorSegments: [String]
        let attribute: String

        if hasAttributeAtEnd {
            selectorSegments = Array(rawSegments.dropLast())
            attribute = normalizeAttributeName(lastSegment)
        } else {
            selectorSegments = rawSegments
            attribute = "text"
        }

        let steps: [LegadoRuleStep]
        if selectorSegments.isEmpty {
            steps = [LegadoRuleStep(selector: "", index: nil, excludeIndex: nil)]
        } else {
            steps = selectorSegments.compactMap(parseSingleStep)
        }

        return LegadoTranslatedValueRule(steps: steps, attribute: attribute, regexTransforms: transforms)
    }

    /// Translates a selector rule (e.g. for `bookList` or `chapterList`) into steps.
    /// e.g. `id.list@tag.dd@tag.a` -> steps: [`#list`, `dd`, `a`]
    static func translateSelectorSteps(_ rawRule: String) -> [LegadoRuleStep] {
        var working = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return [] }

        let lower = working.lowercased()
        if lower.hasPrefix("@css:") {
            working = String(working.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("css:") {
            working = String(working.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let segments = working.components(separatedBy: "@")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return segments.compactMap(parseSingleStep)
    }

    private static func isSelectorToken(_ token: String) -> Bool {
        let lower = token.lowercased()
        if lower.hasPrefix("class.") || lower.hasPrefix("id.") || lower.hasPrefix("tag.") { return true }
        if lower == "children" { return true }
        if lower.hasPrefix(".") || lower.hasPrefix("#") { return true }
        if lower.contains(" ") || lower.contains(">") || lower.contains("[") || lower.contains(":") { return true }
        // Common HTML tag names
        let commonTags: Set<String> = [
            "div", "p", "span", "a", "li", "ul", "ol", "table", "tr", "td", "th",
            "tbody", "thead", "h1", "h2", "h3", "h4", "h5", "h6", "img", "dd",
            "dt", "dl", "article", "section", "header", "footer", "main", "body", "b", "strong", "em", "i"
        ]
        let base = token.components(separatedBy: CharacterSet(charactersIn: ".!:[]")).first?.lowercased() ?? ""
        return commonTags.contains(base)
    }

    private static func parseSingleStep(_ rawStep: String) -> LegadoRuleStep? {
        var step = rawStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !step.isEmpty else { return nil }

        var index: Int? = nil
        var excludeIndex: Int? = nil

        // Check for exclude index: `class.item!0` or `tag.tr!-1`
        if let exclRange = step.range(of: #"!(?:-?\d+)$"#, options: .regularExpression) {
            let exclStr = String(step[exclRange].dropFirst())
            excludeIndex = Int(exclStr)
            step = String(step[..<exclRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Check for index suffix: `.0` or `.-1` or `:eq(0)`
        if let eqRange = step.range(of: #":eq\((-?\d+)\)$"#, options: .regularExpression) {
            let numStr = String(step[eqRange]).dropFirst(4).dropLast()
            index = Int(numStr)
            step = String(step[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let dotIndexRange = step.range(of: #"\.(-?\d+)$"#, options: .regularExpression) {
            let numStr = String(step[dotIndexRange].dropFirst())
            index = Int(numStr)
            step = String(step[..<dotIndexRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let cssSelector = convertLegadoComponentToCSS(step)
        return LegadoRuleStep(selector: cssSelector, index: index, excludeIndex: excludeIndex)
    }

    private static func convertLegadoComponentToCSS(_ component: String) -> String {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("class.") {
            let className = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            return className.isEmpty ? "" : ".\(className.replacingOccurrences(of: " ", with: "."))"
        }
        if lower.hasPrefix("id.") {
            let idName = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return idName.isEmpty ? "" : "#\(idName)"
        }
        if lower.hasPrefix("tag.") {
            let tagName = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            return tagName
        }
        if lower == "children" {
            return "> *"
        }
        if lower.hasPrefix("text.") {
            let targetText = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
            return ":containsOwn(\(targetText))"
        }

        return trimmed
    }
}
