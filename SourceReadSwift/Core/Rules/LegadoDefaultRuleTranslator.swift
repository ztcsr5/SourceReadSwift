import Foundation
import SwiftSoup

struct LegadoRuleStep: Equatable {
    var selector: String
    var index: Int? {
        get { indices?.first }
        set {
            if let newValue {
                indices = [newValue]
            } else {
                indices = nil
            }
        }
    }
    var excludeIndex: Int? {
        get { excludeIndices?.first }
        set {
            if let newValue {
                excludeIndices = [newValue]
            } else {
                excludeIndices = nil
            }
        }
    }
    var indices: [Int]?
    var excludeIndices: [Int]?

    init(selector: String, index: Int? = nil, excludeIndex: Int? = nil, indices: [Int]? = nil, excludeIndices: [Int]? = nil) {
        self.selector = selector
        if let indices {
            self.indices = indices
        } else if let index {
            self.indices = [index]
        } else {
            self.indices = nil
        }
        if let excludeIndices {
            self.excludeIndices = excludeIndices
        } else if let excludeIndex {
            self.excludeIndices = [excludeIndex]
        } else {
            self.excludeIndices = nil
        }
    }
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

    static func parseIndexList(_ text: String) -> (isExclude: Bool, indices: [Int])? {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        var isExclude = false
        if str.hasPrefix("!") {
            isExclude = true
            str = String(str.dropFirst())
        }
        let parts = str.components(separatedBy: ":")
        var result: [Int] = []
        for part in parts {
            let p = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let intVal = Int(p) else { return nil }
            result.append(intVal)
        }
        guard !result.isEmpty else { return nil }
        return (isExclude, result)
    }

    static func isIndexToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseIndexList(trimmed) != nil
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
    /// - `.chapter@1@href`
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
        let hasAttributeAtEnd = isAttributeToken(lastSegment) || (!isSelectorToken(lastSegment) && !isIndexToken(lastSegment) && rawSegments.count > 1)

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
            steps = parseSteps(from: selectorSegments)
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

        return parseSteps(from: segments)
    }

    static func parseSteps(from rawSegments: [String]) -> [LegadoRuleStep] {
        var steps: [LegadoRuleStep] = []
        for segment in rawSegments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if let parsedIndex = parseIndexList(trimmed) {
                if !steps.isEmpty {
                    if parsedIndex.isExclude {
                        steps[steps.count - 1].excludeIndices = parsedIndex.indices
                    } else {
                        steps[steps.count - 1].indices = parsedIndex.indices
                    }
                } else {
                    if parsedIndex.isExclude {
                        steps.append(LegadoRuleStep(selector: "", excludeIndices: parsedIndex.indices))
                    } else {
                        steps.append(LegadoRuleStep(selector: "", indices: parsedIndex.indices))
                    }
                }
                continue
            }

            if let parsed = parseSingleStep(trimmed) {
                steps.append(parsed)
            }
        }
        return steps
    }

    static func executeSteps(_ steps: [LegadoRuleStep], on root: Element) -> [Element] {
        var currentElements = [root]
        for step in steps {
            var nextElements: [Element] = []
            for elem in currentElements {
                do {
                    if step.selector.isEmpty {
                        nextElements.append(elem)
                    } else {
                        let selected = try elem.select(step.selector).array()
                        nextElements.append(contentsOf: selected)
                    }
                } catch {
                    continue
                }
            }
            if let targetIndices = step.indices, !targetIndices.isEmpty {
                var filtered: [Element] = []
                for idx in targetIndices {
                    let normalized = idx >= 0 ? idx : nextElements.count + idx
                    if nextElements.indices.contains(normalized) {
                        filtered.append(nextElements[normalized])
                    }
                }
                currentElements = filtered
            } else if let exclIndices = step.excludeIndices, !exclIndices.isEmpty {
                let normalizedExcls = Set(exclIndices.map { $0 >= 0 ? $0 : nextElements.count + $0 })
                var filtered: [Element] = []
                for (idx, item) in nextElements.enumerated() where !normalizedExcls.contains(idx) {
                    filtered.append(item)
                }
                currentElements = filtered
            } else {
                currentElements = nextElements
            }
        }
        return currentElements
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

        var indices: [Int]? = nil
        var excludeIndices: [Int]? = nil

        // Check for exclude index: `class.item!0` or `tag.tr!-1` or `tag.li.!0:1:-1`
        if let exclRange = step.range(of: #"!(?:-?\d+(?::[^\s@]+)*)$"#, options: .regularExpression) {
            let exclStr = String(step[exclRange].dropFirst())
            if let parsed = parseIndexList(exclStr) {
                excludeIndices = parsed.indices
                step = String(step[..<exclRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if step.hasSuffix(".") { step = String(step.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        } else if let eqRange = step.range(of: #":eq\((-?\d+)\)$"#, options: .regularExpression) {
            let numStr = String(step[eqRange]).dropFirst(4).dropLast()
            if let num = Int(numStr) {
                indices = [num]
            }
            step = String(step[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let dotIndexRange = step.range(of: #"\.(!?-?\d+(?::[^\s@]+)*)$"#, options: .regularExpression) {
            let indexContent = String(step[dotIndexRange].dropFirst())
            if let parsed = parseIndexList(indexContent) {
                if parsed.isExclude {
                    excludeIndices = parsed.indices
                } else {
                    indices = parsed.indices
                }
                step = String(step[..<dotIndexRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let cssSelector = convertLegadoComponentToCSS(step)
        return LegadoRuleStep(selector: cssSelector, indices: indices, excludeIndices: excludeIndices)
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
