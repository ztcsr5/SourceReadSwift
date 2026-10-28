import Foundation
import SwiftSoup

/// One entry of a Legado `[...]` index list.  Legado accepts a plain index
/// (`2`), a range with optional bounds (`8:`, `1:-1`) and a range with a step
/// (`3:-2:-10`); every form accepts negative numbers.
enum LegadoIndexItem: Equatable {
    case single(Int)
    case range(start: Int?, end: Int?, step: Int)
}

struct LegadoRuleStep: Equatable {
    var selector: String
    var indexItems: [LegadoIndexItem]?
    var excludeIndexItems: [LegadoIndexItem]?

    /// Flattened view kept for older call sites and tests.  It returns nil when
    /// the step carries a range, because a range cannot be represented as a
    /// list of single indices without knowing how many elements were selected.
    var indices: [Int]? {
        get { LegadoRuleStep.plainIndices(indexItems) }
        set { indexItems = newValue.map { $0.map(LegadoIndexItem.single) } }
    }

    var excludeIndices: [Int]? {
        get { LegadoRuleStep.plainIndices(excludeIndexItems) }
        set { excludeIndexItems = newValue.map { $0.map(LegadoIndexItem.single) } }
    }

    var index: Int? {
        get {
            guard let first = indexItems?.first, case .single(let value) = first else { return nil }
            return value
        }
        set { indexItems = newValue.map { [.single($0)] } }
    }

    var excludeIndex: Int? {
        get {
            guard let first = excludeIndexItems?.first, case .single(let value) = first else { return nil }
            return value
        }
        set { excludeIndexItems = newValue.map { [.single($0)] } }
    }

    init(
        selector: String,
        index: Int? = nil,
        excludeIndex: Int? = nil,
        indices: [Int]? = nil,
        excludeIndices: [Int]? = nil,
        indexItems: [LegadoIndexItem]? = nil,
        excludeIndexItems: [LegadoIndexItem]? = nil
    ) {
        self.selector = selector
        if let indexItems {
            self.indexItems = indexItems
        } else if let indices {
            self.indexItems = indices.map(LegadoIndexItem.single)
        } else if let index {
            self.indexItems = [.single(index)]
        } else {
            self.indexItems = nil
        }
        if let excludeIndexItems {
            self.excludeIndexItems = excludeIndexItems
        } else if let excludeIndices {
            self.excludeIndexItems = excludeIndices.map(LegadoIndexItem.single)
        } else if let excludeIndex {
            self.excludeIndexItems = [.single(excludeIndex)]
        } else {
            self.excludeIndexItems = nil
        }
    }

    private static func plainIndices(_ items: [LegadoIndexItem]?) -> [Int]? {
        guard let items else { return nil }
        var result: [Int] = []
        result.reserveCapacity(items.count)
        for item in items {
            guard case .single(let value) = item else { return nil }
            result.append(value)
        }
        return result
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

    /// Parses one Legado index list: the text between `[...]` without the
    /// brackets, or the tail of the legacy `.1:3` / `!0:3` form.
    ///
    /// Grammar mirrors `AnalyzeByJSoup.ElementsSingle.findIndexSet`:
    ///   list  := item ("," item)*
    ///   item  := "!"? (index | start? ":" end? (":" step)?)
    ///   index := "-"? digits
    /// - Parameter allowRanges: `true` for the `[...]` bracket form, where
    ///   `1:3` is an inclusive range.  Legacy rules such as `.1:3` / `@1:3`
    ///   use the same separators for a *list of single indices*, so they pass
    ///   `false` and get `1` and `3` instead of `1,2,3`.
    static func parseIndexItems(
        _ text: String,
        allowRanges: Bool = true
    ) -> (isExclude: Bool, items: [LegadoIndexItem])? {
        var str = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return nil }
        var isExclude = false
        if str.hasPrefix("!") {
            isExclude = true
            str = String(str.dropFirst())
        }
        var items: [LegadoIndexItem] = []
        for rawPart in str.split(separator: ",", omittingEmptySubsequences: false) {
            let part = String(rawPart).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !part.isEmpty else { return nil }
            let pieces = part.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            if pieces.count == 1 {
                guard let value = Int(pieces[0]) else { return nil }
                items.append(.single(value))
            } else {
                if !allowRanges {
                    // Legacy form: every colon-separated piece is its own
                    // index, and the list may hold any number of them
                    // (`li!0:1:2:3:4` excludes the first five nodes).
                    var legacyValues: [Int] = []
                    for piece in pieces {
                        let trimmedPiece = piece.trimmingCharacters(in: .whitespaces)
                        guard let value = Int(trimmedPiece) else { return nil }
                        legacyValues.append(value)
                    }
                    items.append(contentsOf: legacyValues.map(LegadoIndexItem.single))
                    continue
                }
                guard pieces.count == 2 || pieces.count == 3 else { return nil }
                let startText = pieces[0].trimmingCharacters(in: .whitespaces)
                let endText = pieces[1].trimmingCharacters(in: .whitespaces)
                var rangeStart: Int?
                if !startText.isEmpty {
                    guard let value = Int(startText) else { return nil }
                    rangeStart = value
                }
                var rangeEnd: Int?
                if !endText.isEmpty {
                    guard let value = Int(endText) else { return nil }
                    rangeEnd = value
                }
                var step = 1
                if pieces.count == 3 {
                    let stepText = pieces[2].trimmingCharacters(in: .whitespaces)
                    if !stepText.isEmpty {
                        guard let value = Int(stepText) else { return nil }
                        step = value
                    }
                }
                items.append(.range(start: rangeStart, end: rangeEnd, step: step))
            }
        }
        guard !items.isEmpty else { return nil }
        return (isExclude, items)
    }

    /// Legacy helper: succeeds only for plain single indices.  Range syntax
    /// returns nil here; callers that must accept ranges use `parseIndexItems`.
    static func parseIndexList(_ text: String) -> (isExclude: Bool, indices: [Int])? {
        guard let parsed = parseIndexItems(text, allowRanges: false) else { return nil }
        var values: [Int] = []
        for item in parsed.items {
            guard case .single(let value) = item else { return nil }
            values.append(value)
        }
        return (parsed.isExclude, values)
    }

    static func isIndexToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseIndexItems(trimmed) != nil
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
        if working.hasPrefix("+") || working.hasPrefix("-") {
            working = String(working.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !working.isEmpty else { return nil }

        // Legado's `@attr` rule addresses the current node directly: the whole
        // rule is an attribute name, not a CSS selector.  Splitting on `@`
        // below drops the marker and turns `@onclick` into the tag selector
        // `onclick`, which never matches.  Bind `@href`, `@text`, `@onclick`,
        // `@data-src` and `@attr:name` to the current element here.
        let leadingLower = working.lowercased()
        if working.hasPrefix("@"),
           !leadingLower.hasPrefix("@css:"),
           !leadingLower.hasPrefix("@json:"),
           !leadingLower.hasPrefix("@js:"),
           !leadingLower.hasPrefix("@xpath:") {
            let attrParts = working.components(separatedBy: "##")
            let attribute = normalizeAttributeName(attrParts.first ?? working)
            guard !attribute.isEmpty else { return nil }
            return LegadoTranslatedValueRule(
                steps: [LegadoRuleStep(selector: "")],
                attribute: attribute,
                regexTransforms: Array(attrParts.dropFirst())
            )
        }

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
        if working.hasPrefix("+") || working.hasPrefix("-") {
            working = String(working.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
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

            if let parsedIndex = parseIndexItems(trimmed, allowRanges: false) {
                if !steps.isEmpty {
                    if parsedIndex.isExclude {
                        steps[steps.count - 1].excludeIndexItems = parsedIndex.items
                    } else {
                        steps[steps.count - 1].indexItems = parsedIndex.items
                    }
                } else {
                    if parsedIndex.isExclude {
                        steps.append(LegadoRuleStep(selector: "", excludeIndexItems: parsedIndex.items))
                    } else {
                        steps.append(LegadoRuleStep(selector: "", indexItems: parsedIndex.items))
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
            if let targetItems = step.indexItems, !targetItems.isEmpty {
                let selected = resolveIndexSet(targetItems, count: nextElements.count)
                currentElements = selected.map { nextElements[$0] }
            } else if let exclItems = step.excludeIndexItems, !exclItems.isEmpty {
                let excluded = Set(resolveIndexSet(exclItems, count: nextElements.count))
                var filtered: [Element] = []
                for (idx, item) in nextElements.enumerated() where !excluded.contains(idx) {
                    filtered.append(item)
                }
                currentElements = filtered
            } else {
                currentElements = nextElements
            }
        }
        return currentElements
    }

    /// Expands a Legado index list against a concrete element count and returns
    /// the ordered, de-duplicated index set.  Mirrors
    /// `AnalyzeByJSoup.ElementsSingle.getElementsSingle`:
    ///  - negative indices count from the end, out-of-range entries are dropped;
    ///  - omitted range bounds mean first/last element;
    ///  - `start == end`, or a step at least as large as the list, keeps only
    ///    the start index;
    ///  - `end < start` walks backwards, which is how `[-1:0]` reverses a list.
    private static func resolveIndexSet(_ items: [LegadoIndexItem], count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var seen = Set<Int>()
        var ordered: [Int] = []

        func append(_ index: Int) {
            guard index >= 0, index < count, !seen.contains(index) else { return }
            seen.insert(index)
            ordered.append(index)
        }

        for item in items {
            switch item {
            case .single(let raw):
                append(raw >= 0 ? raw : raw + count)
            case .range(let rawStart, let rawEnd, let rawStep):
                var rangeStart = rawStart ?? 0
                if rangeStart < 0 { rangeStart += count }
                var rangeEnd = rawEnd ?? (count - 1)
                if rangeEnd < 0 { rangeEnd += count }
                if (rangeStart < 0 && rangeEnd < 0) || (rangeStart >= count && rangeEnd >= count) {
                    continue
                }
                rangeStart = min(max(rangeStart, 0), count - 1)
                rangeEnd = min(max(rangeEnd, 0), count - 1)
                if rangeStart == rangeEnd || rawStep >= count {
                    append(rangeStart)
                    continue
                }
                let step: Int
                if rawStep > 0 {
                    step = rawStep
                } else if -rawStep < count {
                    step = max(rawStep + count, 1)
                } else {
                    step = 1
                }
                if rangeEnd > rangeStart {
                    var index = rangeStart
                    while index <= rangeEnd {
                        append(index)
                        index += step
                    }
                } else {
                    var index = rangeStart
                    while index >= rangeEnd {
                        append(index)
                        index -= step
                    }
                }
            }
        }
        return ordered
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

        var indexItems: [LegadoIndexItem]? = nil
        var excludeIndexItems: [LegadoIndexItem]? = nil

        // `[...]` list: `.row[-1]`, `tag.a[1:3]`, `tr[!0]`, `.list[8:]`, `li[1:-1]`
        if let bracketRange = step.range(of: #"\[(!?[\d:,-]+)\]$"#, options: .regularExpression) {
            let inner = String(step[bracketRange].dropFirst().dropLast())
            if let parsed = parseIndexItems(inner) {
                if parsed.isExclude {
                    excludeIndexItems = parsed.items
                } else {
                    indexItems = parsed.items
                }
                step = String(step[..<bracketRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else if let exclRange = step.range(of: #"!([\d:,-]+)$"#, options: .regularExpression) {
            let exclStr = String(step[exclRange].dropFirst())
            if let parsed = parseIndexItems(exclStr, allowRanges: false) {
                excludeIndexItems = parsed.items
                step = String(step[..<exclRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if step.hasSuffix(".") { step = String(step.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        } else if let eqRange = step.range(of: #":eq\((-?\d+)\)$"#, options: .regularExpression) {
            let numStr = String(step[eqRange]).dropFirst(4).dropLast()
            if let num = Int(numStr) {
                indexItems = [.single(num)]
            }
            step = String(step[..<eqRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let dotIndexRange = step.range(of: #"\.(!?[\d:,-]+)$"#, options: .regularExpression) {
            let indexContent = String(step[dotIndexRange].dropFirst())
            if let parsed = parseIndexItems(indexContent, allowRanges: false) {
                if parsed.isExclude {
                    excludeIndexItems = parsed.items
                } else {
                    indexItems = parsed.items
                }
                step = String(step[..<dotIndexRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let cssSelector = convertLegadoComponentToCSS(step)
        return LegadoRuleStep(selector: cssSelector, indexItems: indexItems, excludeIndexItems: excludeIndexItems)
    }

    private static let compoundHTMLTagNames: Set<String> = [
        "ul", "ol", "li", "dl", "dt", "dd", "div", "span", "p", "a",
        "h1", "h2", "h3", "h4", "h5", "h6", "table", "tr", "td", "th",
        "tbody", "thead", "img", "section", "article", "header", "footer",
        "nav", "main", "em", "strong", "i", "b"
    ]

    private static func convertLegadoComponentToCSS(_ component: String) -> String {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.hasPrefix("class.") {
            let className = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !className.isEmpty else { return "" }
            let normalizedClass = className.replacingOccurrences(of: " ", with: ".")
            if normalizedClass.contains(".") {
                let parts = normalizedClass.split(separator: ".").map(String.init)
                if parts.count >= 2, let lastTag = parts.last?.lowercased(), compoundHTMLTagNames.contains(lastTag) {
                    let classPrefix = parts.dropLast().joined(separator: ".")
                    return ".\(classPrefix) \(lastTag), .\(normalizedClass)"
                }
            }
            return ".\(normalizedClass)"
        }
        if lower.hasPrefix("id.") {
            let idName = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !idName.isEmpty else { return "" }
            if idName.contains(".") {
                let parts = idName.split(separator: ".").map(String.init)
                if parts.count >= 2, let lastTag = parts.last?.lowercased(), compoundHTMLTagNames.contains(lastTag) {
                    let idPrefix = parts.dropLast().joined(separator: ".")
                    let escapedFull = idName.replacingOccurrences(of: ".", with: "\\.")
                    return "#\(idPrefix) \(lastTag), #\(escapedFull)"
                }
            }
            return "#\(idName)"
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
