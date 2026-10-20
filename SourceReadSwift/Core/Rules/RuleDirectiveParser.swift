import Foundation

/// Balanced scanner for Legado `@put:{...}` / `@get:{...}` directives.
///
/// `@put` bodies are not JSON: a value may be a JS snippet, a `##regex##`
/// transform, or a quoted string containing braces.  The old
/// `@put:\{[^}]*\}` regular expression stopped at the first `}`, which silently
/// dropped every following field.  The HTML and JSON extractors share this
/// scanner so both dialects accept the same bodies.
enum RuleDirectiveParser {
    struct Span {
        let range: Range<String.Index>
        let body: String
    }

    // MARK: - Scanning

    /// Finds every `<marker>{...}` span.  Quotes, backslash escapes, nested
    /// braces and `##regex##` sections are skipped while balancing.
    static func spans(in rule: String, marker: String) -> [Span] {
        guard !marker.isEmpty else { return [] }
        var spans: [Span] = []
        var searchStart = rule.startIndex
        while searchStart < rule.endIndex,
              let markerRange = rule.range(of: marker, options: .caseInsensitive, range: searchStart..<rule.endIndex) {
            var braceStart = markerRange.upperBound
            while braceStart < rule.endIndex, rule[braceStart].isWhitespace {
                braceStart = rule.index(after: braceStart)
            }
            guard braceStart < rule.endIndex,
                  rule[braceStart] == "{",
                  let closing = matchingBrace(in: rule, from: braceStart) else {
                searchStart = markerRange.upperBound
                continue
            }
            let bodyStart = rule.index(after: braceStart)
            spans.append(Span(
                range: markerRange.lowerBound..<rule.index(after: closing),
                body: String(rule[bodyStart..<closing])
            ))
            searchStart = rule.index(after: closing)
        }
        return spans
    }

    /// Returns the `}` that closes `open`, or `nil` when the brace never
    /// closes.  A second pass without regex awareness handles malformed rules
    /// where an odd `##` is not a transform delimiter.
    static func matchingBrace(in text: String, from open: String.Index) -> String.Index? {
        guard open < text.endIndex, text[open] == "{" else { return nil }
        if let closing = scanMatchingBrace(in: text, from: open, honoringRegex: true) {
            return closing
        }
        return scanMatchingBrace(in: text, from: open, honoringRegex: false)
    }

    private static func scanMatchingBrace(
        in text: String,
        from open: String.Index,
        honoringRegex: Bool
    ) -> String.Index? {
        var depth = 0
        var quote: Character?
        var escaped = false
        var index = open
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)

            if escaped {
                escaped = false
                index = next
                continue
            }
            if character == "\\" {
                escaped = true
                index = next
                continue
            }
            if honoringRegex, character == "#", next < text.endIndex, text[next] == "#" {
                if let afterRegex = indexAfterRegexPattern(in: text, at: index) {
                    index = afterRegex
                    continue
                }
            }
            if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" || character == "`" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return index }
            }
            index = next
        }
        return nil
    }

    /// Legado transforms are `path##pattern##replacement##flag`, so the first
    /// `##...##` pair is the regex pattern.  Its content is opaque for brace
    /// balancing (`##[}]+##`, `##\}$##`).
    private static func indexAfterRegexPattern(in text: String, at start: String.Index) -> String.Index? {
        var search = text.index(after: text.index(after: start))
        while search < text.endIndex {
            let next = text.index(after: search)
            if text[search] == "#", next < text.endIndex, text[next] == "#" {
                return text.index(after: next)
            }
            search = next
        }
        return nil
    }

    // MARK: - @put

    /// Parses every `@put:{...}` in `rule`.
    static func putPairs(in rule: String) -> [(key: String, valueRule: String)] {
        spans(in: rule, marker: "@put:").flatMap { parsePutBody($0.body) }
    }

    /// Parses one `@put` body.  A body may hold several comma-separated
    /// fields; each value keeps everything after its first top-level colon so
    /// regex and JS values containing `:` stay intact.
    static func parsePutBody(_ rawBody: String) -> [(key: String, valueRule: String)] {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return [] }

        // `@put:{{"key":"rule"}}` — the body is itself a JSON object.
        if body.hasPrefix("{"), body.hasSuffix("}"),
           let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let dictionary = object as? [String: Any] {
            return dictionary
                .map { (key: $0.key, valueRule: jsonRuleString($0.value)) }
                .filter { !$0.key.isEmpty && !$0.valueRule.isEmpty }
                .sorted { $0.key < $1.key }
        }

        return splitTopLevel(body, separator: ",").compactMap { entry in
            let trimmedEntry = entry.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedEntry.isEmpty else { return nil }
            let parts = splitTopLevel(trimmedEntry, separator: ":", maxSplits: 1)
            if parts.count == 1 {
                let key = unquote(trimmedEntry)
                return key.isEmpty ? nil : (key, "")
            }
            let key = unquote(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
            let valueRule = unquote(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
            guard !key.isEmpty else { return nil }
            return (key, valueRule)
        }
    }

    static func removingPuts(from rule: String) -> String {
        let spans = spans(in: rule, marker: "@put:")
        guard !spans.isEmpty else { return rule }
        var output = rule
        for span in spans.reversed() {
            output.removeSubrange(span.range)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - @get

    /// Replaces `@get:{key}` and bare `@get:key` with `resolver(key)`.
    /// Trailing text (`/book/1`, `##regex##`) is preserved for the caller.
    static func replacingGets(in rule: String, resolver: (String) -> String) -> String {
        var output = ""
        var index = rule.startIndex
        while index < rule.endIndex {
            guard let range = rule.range(of: "@get:", options: .caseInsensitive, range: index..<rule.endIndex) else {
                output.append(contentsOf: rule[index...])
                break
            }
            output.append(contentsOf: rule[index..<range.lowerBound])
            var after = range.upperBound
            while after < rule.endIndex, rule[after].isWhitespace {
                after = rule.index(after: after)
            }
            if after < rule.endIndex, rule[after] == "{",
               let closing = matchingBrace(in: rule, from: after) {
                let key = unquote(String(rule[rule.index(after: after)..<closing])
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                output.append(resolver(key))
                index = rule.index(after: closing)
                continue
            }
            var cursor = after
            while cursor < rule.endIndex, isBareKeyCharacter(rule[cursor]) {
                cursor = rule.index(after: cursor)
            }
            let key = unquote(String(rule[after..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines))
            output.append(resolver(key))
            index = cursor
        }
        return output
    }

    private static func isBareKeyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == "$"
    }

    // MARK: - Shared helpers

    /// Splits on a separator that sits outside quotes, escapes, brackets,
    /// braces, parentheses and `##regex##` patterns.
    static func splitTopLevel(
        _ text: String,
        separator: Character,
        maxSplits: Int = Int.max
    ) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var braceDepth = 0
        var bracketDepth = 0
        var parenDepth = 0
        var splits = 0
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)

            if escaped {
                current.append(character)
                escaped = false
                index = next
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                index = next
                continue
            }
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                index = next
                continue
            }
            if character == "#", next < text.endIndex, text[next] == "#",
               let afterRegex = indexAfterRegexPattern(in: text, at: index) {
                current.append(contentsOf: text[index..<afterRegex])
                index = afterRegex
                continue
            }
            switch character {
            case "\"", "'", "`":
                quote = character
                current.append(character)
            case "{":
                braceDepth += 1
                current.append(character)
            case "}":
                braceDepth = max(0, braceDepth - 1)
                current.append(character)
            case "[":
                bracketDepth += 1
                current.append(character)
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
                current.append(character)
            case "(":
                parenDepth += 1
                current.append(character)
            case ")":
                parenDepth = max(0, parenDepth - 1)
                current.append(character)
            default:
                if character == separator,
                   braceDepth == 0,
                   bracketDepth == 0,
                   parenDepth == 0,
                   splits < maxSplits {
                    parts.append(current)
                    current = ""
                    splits += 1
                } else {
                    current.append(character)
                }
            }
            index = next
        }
        parts.append(current)
        return parts
    }

    static func unquote(_ value: String) -> String {
        var output = value
        if output.count >= 2,
           let first = output.first,
           let last = output.last,
           (first == "\"" || first == "'" || first == "`"),
           first == last {
            output = String(output.dropFirst().dropLast())
        }
        return output
    }

    private static func jsonRuleString(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}