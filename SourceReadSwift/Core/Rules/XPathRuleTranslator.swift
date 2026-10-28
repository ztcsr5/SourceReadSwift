import Foundation

struct XPathRuleTranslator {
    static func valueRule(_ rawRule: String) -> (selector: String, attribute: String)? {
        let parts = rawRule.components(separatedBy: "##")
        guard let translated = translate(parts.first ?? rawRule) else { return nil }
        let suffix = parts.count > 1 ? "##" + parts.dropFirst().joined(separator: "##") : ""
        return (translated.selector, translated.attribute + suffix)
    }

    static func selectorRule(_ rawRule: String) -> String? {
        translate(rawRule)?.selector
    }

    private static func translate(_ rawRule: String) -> (selector: String, attribute: String)? {
        var rule = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = rule.lowercased()
        if lower.hasPrefix("@xpath:") {
            rule = String(rule.dropFirst(7))
        } else if lower.hasPrefix("xpath:") {
            rule = String(rule.dropFirst(6))
        }
        guard rule.hasPrefix("//") || rule.hasPrefix("/") else { return nil }
        // Axes that cannot be expressed with jsoup selectors are rejected as a
        // whole instead of silently dropping a step (a dropped step returns
        // rows from the wrong level of the page).
        let unsupportedAxes = ["parent::", "ancestor::", "preceding-sibling::", "preceding::", "following::"]
        if unsupportedAxes.contains(where: { rule.lowercased().contains($0) }) {
            return nil
        }

        var attribute = "text"
        if rule.hasSuffix("/text()") {
            rule.removeLast("/text()".count)
            attribute = "text"
        } else if rule.hasSuffix("/@href") {
            rule.removeLast("/@href".count)
            attribute = "href"
        } else if rule.hasSuffix("/@src") {
            rule.removeLast("/@src".count)
            attribute = "src"
        } else if rule.hasSuffix("/@content") {
            rule.removeLast("/@content".count)
            attribute = "content"
        } else if let attrRange = rule.range(of: #"/@([A-Za-z_][A-Za-z0-9_:\-]*)$"#, options: .regularExpression) {
            attribute = String(String(rule[attrRange]).dropFirst(2))
            rule.removeSubrange(attrRange)
        }

        let selector = cssSelector(from: rule)
        guard !selector.isEmpty else { return nil }
        return (selector, attribute)
    }

    private static func cssSelector(from xpath: String) -> String {
        let normalized = xpath
            .replacingOccurrences(of: #"^/+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"/+"#, with: "/", options: .regularExpression)
        let steps = normalized
            .components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." }
        // XPath positional predicates are 1-based and scoped to the parent's
        // same-type children, which is exactly `:nth-of-type`. The legacy `@n`
        // suffix only works on the final step (the extractor strips it), so an
        // axis rule such as `//dt[2]/following-sibling::dd/a` must keep the
        // position inside the selector.
        let usesAxes = steps.contains { $0.contains("::") }
        // XPath positional predicates are scoped to the parent's same-type
        // children at every step. The legacy `@n` suffix indexes the final
        // match list, which is only equivalent for a single-step path: a
        // relative field rule such as `/span[2]/a/text()` (used by the
        // novelslist2 sources) would otherwise translate to `span@1 a` and
        // select nothing.
        let useNthOfType = usesAxes || steps.count > 1
        return steps.compactMap { cssStep($0, useNthOfType: useNthOfType) }.joined(separator: " ")
    }

    private static func cssStep(_ rawStep: String, useNthOfType: Bool) -> String? {
        var step = rawStep
        var combinator = ""
        if let range = step.range(of: #"^following-sibling\s*::\s*"#, options: .regularExpression) {
            step = String(step[range.upperBound...])
            combinator = "~ "
        } else if let range = step.range(of: #"^child\s*::\s*"#, options: .regularExpression) {
            step = String(step[range.upperBound...])
            combinator = "> "
        } else if let range = step.range(of: #"^descendant\s*::\s*"#, options: .regularExpression) {
            step = String(step[range.upperBound...])
        } else if let range = step.range(of: #"^self\s*::\s*"#, options: .regularExpression) {
            step = String(step[range.upperBound...])
        } else if step.contains("::") {
            return nil
        }
        step = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !step.isEmpty else { return nil }
        if step == "*" { return combinator + "*" }
        guard let tagRange = step.range(of: #"^(?:[A-Za-z][A-Za-z0-9_\-]*|\*)"#, options: .regularExpression) else {
            return nil
        }
        let tag = String(step[tagRange])
        let predicateText = step[tagRange.upperBound...]
        var selector = tag
        var indexSuffix = ""

        for rawPredicate in predicates(String(predicateText)) {
            for predicate in splitCompoundPredicates(rawPredicate) {
                if let fragment = cssPredicate(predicate) {
                    selector += fragment
                } else if let index = indexPredicate(predicate) {
                    if useNthOfType {
                        selector += index < 0 ? ":last-of-type" : ":nth-of-type(\(index + 1))"
                    } else {
                        indexSuffix = "@\(index)"
                    }
                }
            }
        }
        // `*#list` / `*.chapter` is legal CSS but some jsoup versions only
        // resolve the class/id when the universal tag is omitted.
        if selector.hasPrefix("*"), selector.count > 1 {
            let rest = selector.dropFirst()
            if rest.hasPrefix(".") || rest.hasPrefix("#") || rest.hasPrefix("[") {
                selector = String(rest)
            }
        }
        return combinator + selector + indexSuffix
    }

    private static func splitCompoundPredicates(_ predicate: String) -> [String] {
        var result: [String] = []
        var buffer = ""
        var quote: Character?
        let chars = Array(predicate)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if let currentQuote = quote {
                buffer.append(ch)
                if ch == currentQuote {
                    quote = nil
                }
                i += 1
                continue
            }
            if ch == "'" || ch == "\"" {
                quote = ch
                buffer.append(ch)
                i += 1
                continue
            }
            if i + 5 <= chars.count {
                let slice = String(chars[i..<(i + 5)])
                if slice.lowercased() == " and " {
                    let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        result.append(trimmed)
                    }
                    buffer = ""
                    i += 5
                    continue
                }
            }
            buffer.append(ch)
            i += 1
        }
        let trailing = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            result.append(trailing)
        }
        return result
    }

    private static func predicates(_ text: String) -> [String] {
        var output: [String] = []
        var start: String.Index?
        var depth = 0
        for index in text.indices {
            let char = text[index]
            if char == "[" {
                if depth == 0 { start = text.index(after: index) }
                depth += 1
            } else if char == "]" {
                depth = max(0, depth - 1)
                if depth == 0, let start {
                    output.append(String(text[start..<index]).trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }
        return output
    }

    private static func cssPredicate(_ predicate: String) -> String? {
        let trimmed = predicate.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = capture(trimmed, pattern: #"^@id\s*=\s*['"]([^'"]+)['"]$"#) {
            return "#\(escapeIdentifier(value))"
        }
        if let value = capture(trimmed, pattern: #"^@class\s*=\s*['"]([^'"]+)['"]$"#) {
            return value
                .split(whereSeparator: { $0.isWhitespace })
                .map { ".\(escapeIdentifier(String($0)))" }
                .joined()
        }
        if let value = capture(trimmed, pattern: #"^contains\(\s*@class\s*,\s*['"]([^'"]+)['"]\s*\)$"#) {
            return ".\(escapeIdentifier(value))"
        }
        if let match = capturePair(trimmed, pattern: #"^@([A-Za-z_][A-Za-z0-9_:\-]*)\s*=\s*['"]([^'"]+)['"]$"#) {
            return "[\(match.0)=\"\(match.1)\"]"
        }
        if let attr = capture(trimmed, pattern: #"^@([A-Za-z_][A-Za-z0-9_:\-]*)$"#) {
            return "[\(attr)]"
        }
        if let numStr = capture(trimmed, pattern: #"^position\(\)\s*>\s*(\d+)$"#),
           let n = Int(numStr), n >= 1 {
            return ":gt(\(n - 1))"
        }
        if let numStr = capture(trimmed, pattern: #"^position\(\)\s*>=\s*(\d+)$"#),
           let n = Int(numStr) {
            return n >= 2 ? ":gt(\(n - 2))" : ""
        }
        if capture(trimmed, pattern: #"^(position\(\)\s*<\s*last\(\))$"#) != nil {
            return ":not(:last-child)"
        }
        if capture(trimmed, pattern: #"^(position\(\)\s*<=\s*last\(\)\s*-\s*1)$"#) != nil {
            return ":not(:last-child)"
        }
        if capture(trimmed, pattern: #"^(position\(\)\s*==?\s*last\(\)|last\(\))$"#) != nil {
            return ":last-child"
        }
        if let numStr = capture(trimmed, pattern: #"^position\(\)\s*<\s*(\d+)$"#),
           let n = Int(numStr), n >= 2 {
            return ":lt(\(n - 1))"
        }
        if let numStr = capture(trimmed, pattern: #"^position\(\)\s*<=\s*(\d+)$"#),
           let n = Int(numStr), n >= 1 {
            return ":lt(\(n))"
        }
        return nil
    }

    private static func indexPredicate(_ predicate: String) -> Int? {
        let trimmed = predicate.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "last()" { return -1 }
        guard let oneBased = Int(trimmed), oneBased > 0 else { return nil }
        return oneBased - 1
    }

    private static func capture(_ text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[valueRange])
    }

    private static func capturePair(_ text: String, pattern: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 2,
              let firstRange = Range(match.range(at: 1), in: text),
              let secondRange = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[firstRange]), String(text[secondRange]))
    }

    private static func escapeIdentifier(_ value: String) -> String {
        value.replacingOccurrences(of: #"([^A-Za-z0-9_\-])"#, with: #"\\$1"#, options: .regularExpression)
    }
}
