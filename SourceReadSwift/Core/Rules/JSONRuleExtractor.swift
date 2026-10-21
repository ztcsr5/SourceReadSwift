import Foundation
import SwiftSoup

final class JSONRuleDirectiveStore {
    private var values: [String: Any] = [:]

    func put(_ key: String, value: Any) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        values[clean] = value
    }

    func get(_ key: String) -> Any? {
        values[key.trimmingCharacters(in: .whitespacesAndNewlines)]
    }
}

struct JSONRuleExtractor {
    private enum DirectiveResult {
        case path(String)
        case value(Any)
    }

    private enum SourceSegment {
        case normal(String)
        case js(String)
    }

    private struct FilterClause {
        let path: String
        let op: String?
        let expected: String?
    }

    private enum FilterLiteral {
        case bool(Bool)
        case number(Double)
        case string(String)
        indirect case array([FilterLiteral])
    }

    private typealias RegexTransform = RuleRegexTransform

    private let directiveStore: JSONRuleDirectiveStore
    private let executionContext: RuleExecutionContext

    init(
        directiveStore: JSONRuleDirectiveStore = JSONRuleDirectiveStore(),
        executionContext: RuleExecutionContext = RuleExecutionContext()
    ) {
        self.directiveStore = directiveStore
        self.executionContext = executionContext
    }

    func list(from object: Any, rule: String?, variables: [String: Any] = [:]) -> [[String: Any]] {
        let trimmed = rule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return rootDictionaryList(from: object)
        }
        guard let selected = value(from: object, path: trimmed, variables: variables) else {
            return []
        }
        return dictionaries(from: selected)
    }

    func string(
        from object: Any,
        rule: String?,
        fallbackKeys: [String] = [],
        variables: [String: Any] = [:]
    ) -> String? {
        if let dict = object as? [String: Any] {
            return string(from: dict, rule: rule, fallbackKeys: fallbackKeys, variables: variables)
        }
        let trimmed = rule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        if let extracted = value(from: object, path: trimmed, variables: variables) {
            let text = stringifyJSResult(extracted)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    func string(
        from item: [String: Any],
        rule: String?,
        fallbackKeys: [String] = [],
        variables: [String: Any] = [:]
    ) -> String? {
        if let rule {
            let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("{{") && trimmed.contains("}}") {
                if let evaluated = evaluateTemplateSegments(trimmed, item: item, variables: variables) {
                    let text = stringifyJSResult(evaluated).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        if text.hasPrefix("http://") || text.hasPrefix("https://") || text.hasPrefix("/") {
                            let cleanedURL = splitTransforms(text).path
                            if !cleanedURL.isEmpty { return cleanedURL }
                        }
                        return text
                    }
                }
            }
            if let value = value(from: item, path: rule, variables: variables) {
                let text = stringifyJSResult(value)
                if !text.isEmpty { return text }
            }
        }
        for key in fallbackKeys {
            if let value = item[key] {
                let text = stringifyJSResult(value)
                if !text.isEmpty { return text }
            }
            let lowerKey = key.lowercased()
            if let matchKey = item.keys.first(where: { $0.lowercased() == lowerKey }),
               let value = item[matchKey] {
                let text = stringifyJSResult(value)
                if !text.isEmpty { return text }
            }
        }
        return nil
    }

    func stringList(
        from object: Any,
        rule: String?,
        variables: [String: Any] = [:]
    ) -> [String] {
        let trimmed = rule?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return [] }

        // `AnalyzeByJSonPath.getStringList` never splits plain strings: each
        // JSONPath match (and each successful `{$...}` inner-rule replacement)
        // becomes exactly one element, even when the text contains newlines.
        let split = splitTransforms(trimmed)
        let pathPart = split.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let isScriptRule = trimmed.contains("@js:")
            || trimmed.hasPrefix("<js>")
            || trimmed.contains("<js>")

        // Legado splits the rule on the first top-level `&&`, `||` or `%%`
        // *before* evaluating any branch, and each branch keeps its own list
        // shape: `&&` concatenates, `||` keeps the first non-empty list and
        // `%%` interleaves element-wise.  Expanding `{$...}` across the whole
        // rule first would turn `{$..title}&&{$..id}` into one glued string.
        if !isScriptRule, let operation = RuleOperatorSplitter.firstOperator(in: pathPart) {
            let lists = operation.parts.map {
                stringList(from: object, rule: $0, variables: variables)
            }
            var merged: [String] = []
            switch operation.op {
            case "||":
                merged = lists.first(where: { !$0.isEmpty }) ?? []
            case "%%":
                if let first = lists.first {
                    for index in first.indices {
                        for list in lists where index < list.count {
                            merged.append(list[index])
                        }
                    }
                }
            default:
                for list in lists { merged.append(contentsOf: list) }
            }
            return applyTransforms(split.transforms, to: merged)
        }

        if !isScriptRule, pathPart.contains("{$."),
           let expanded = expandInnerJSONRules(in: pathPart, object: object, variables: variables) {
            let transformed = applyTransforms(split.transforms, to: expanded)
            let text = stringifyJSResult(transformed)
            return text.isEmpty ? [] : [text]
        }

        guard let selected = value(from: object, path: trimmed, variables: variables) else {
            return []
        }
        return listValues(from: selected)
    }

    func value(from object: Any, path rawPath: String, variables: [String: Any] = [:]) -> Any? {
        var rule = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return object }
        if rule.lowercased().hasPrefix("@json:") {
            rule = String(rule.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !rule.isEmpty else { return object }

        let segments = splitSourceSegments(rule)
        guard !segments.isEmpty else { return object }
        if segments.count == 1, case .normal(let only) = segments[0] {
            return evaluateNormalSegment(only, object: object, variables: variables)
        }

        var current: Any = object
        for segment in segments {
            switch segment {
            case .normal(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                guard let next = evaluateNormalSegment(trimmed, object: current, variables: variables) else {
                    return nil
                }
                current = next
            case .js(let code):
                guard let next = evaluateRawJS(script: code, object: current, extraVariables: variables) else {
                    return nil
                }
                current = next
            }
        }
        return current
    }

    private func splitSourceSegments(_ rule: String) -> [SourceSegment] {
        var segments: [SourceSegment] = []
        var remaining = rule

        if remaining.hasPrefix("@js:") {
            let code = String(remaining.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !code.isEmpty { segments.append(.js(code)) }
            return segments
        }

        while let start = remaining.range(of: "<js>") {
            let before = String(remaining[..<start.lowerBound])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.normal(before))
            }
            guard let end = remaining.range(of: "</js>", range: start.upperBound..<remaining.endIndex) else {
                let code = String(remaining[start.upperBound...])
                if !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.js(code))
                }
                return segments
            }
            let code = String(remaining[start.upperBound..<end.lowerBound])
            segments.append(.js(code))
            remaining = String(remaining[end.upperBound...])
        }

        if !remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.normal(remaining))
        }
        return segments
    }

    private func evaluateNormalSegment(
        _ rawRule: String,
        object: Any,
        variables: [String: Any]
    ) -> Any? {
        let rule = rawRule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rule.isEmpty else { return object }

        if rule.hasPrefix("@js:") || rule.hasPrefix("<js>") {
            return evaluateJS(rule: rule, object: object, extraVariables: variables)
        }
        if let jsRange = rule.range(of: "@js:") {
            let left = String(rule[..<jsRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(rule[jsRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let intermediate: Any?
            if left.isEmpty {
                intermediate = object
            } else {
                intermediate = evaluateNormalSegment(left, object: object, variables: variables)
            }
            guard let intermediate else { return nil }
            return evaluateJS(rule: "@js:" + right, object: intermediate, extraVariables: variables)
        }

        if let direct = directGetDirective(in: rule) {
            return resolvedDirectGet(direct)
        }

        let directiveResult = applyDirectives(from: object, path: rule, variables: variables)
        var pathPart: String
        var transforms: [RegexTransform]
        switch directiveResult {
        case .value(let stored):
            return stored
        case .path(let cleaned):
            let split = splitTransforms(cleaned)
            pathPart = split.path.trimmingCharacters(in: .whitespacesAndNewlines)
            transforms = split.transforms
        }

        if let jsonRange = pathPart.range(of: "@json:") {
            let left = String(pathPart[..<jsonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(pathPart[jsonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let intermediate: Any?
            if left.isEmpty {
                intermediate = object
            } else {
                intermediate = evaluateNormalSegment(left, object: object, variables: variables)
            }
            guard let intermediate else { return nil }
            let decoded = decodeJSONValue(intermediate) ?? intermediate
            guard let result = value(from: decoded, path: right, variables: variables) else { return nil }
            return applyTransforms(transforms, to: result)
        }

        guard !pathPart.isEmpty else {
            return applyTransforms(transforms, to: object)
        }

        if let operation = RuleOperatorSplitter.firstOperator(in: pathPart) {
            let directValues = operation.parts.map {
                evaluateBranch($0, object: object, variables: variables)
            }
            // Legado chains rules like "Data&&Books" as nested traversal when a
            // later part cannot resolve against the original object. Rules whose
            // parts all resolve at the same level keep the merge semantics.
            if operation.op == "&&",
               directValues.dropFirst().contains(where: { $0 == nil }) {
                var current: Any? = object
                var chained = true
                for part in operation.parts {
                    guard let base = current,
                          let next = evaluateBranch(part, object: base, variables: variables) else {
                        chained = false
                        break
                    }
                    current = next
                }
                if chained, let final = current {
                    return applyTransforms(transforms, to: final)
                }
            }
            let values = directValues.compactMap { $0 }
            guard let merged = merge(values: values, operation: operation.op) else { return nil }
            return applyTransforms(transforms, to: merged)
        }

        if let expanded = expandInnerJSONRules(in: pathPart, object: object, variables: variables) {
            return applyTransforms(transforms, to: expanded)
        }

        guard let selected = valueForSinglePath(from: object, path: pathPart) else { return nil }
        return applyTransforms(transforms, to: selected)
    }
    private func evaluateBranch(
        _ raw: String,
        object: Any,
        variables: [String: Any]
    ) -> Any? {
        let part = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !part.isEmpty else { return nil }
        if let operation = RuleOperatorSplitter.firstOperator(in: part) {
            let values = operation.parts.compactMap {
                evaluateBranch($0, object: object, variables: variables)
            }
            return merge(values: values, operation: operation.op)
        }
        if part.hasPrefix("@js:") || part.hasPrefix("<js>") || part.contains("@js:") {
            return evaluateNormalSegment(part, object: object, variables: variables)
        }
        if let expanded = expandInnerJSONRules(in: part, object: object, variables: variables) {
            return expanded
        }
        return valueForSinglePath(from: object, path: part)
    }

    /// Legado's `AnalyzeByJSonPath.getString` replaces every balanced
    /// `{$...}` inner rule before evaluating the JSONPath.  The replacement
    /// is textual: `prefix{$..title}suffix` becomes `prefixTitleSuffix`, and
    /// any rule that produced at least one replacement is returned as-is
    /// instead of being parsed as a path again.  Unresolved inner rules stay
    /// verbatim, matching `RuleAnalyzer.innerRule`.
    private func expandInnerJSONRules(
        in rule: String,
        object: Any,
        variables: [String: Any],
        depth: Int = 0
    ) -> String? {
        guard depth < 16, rule.contains("{$.") else { return nil }
        var output = ""
        var index = rule.startIndex
        var replaced = false
        while index < rule.endIndex {
            guard let start = rule.range(of: "{$.", range: index..<rule.endIndex) else {
                output += rule[index...]
                break
            }
            output += rule[index..<start.lowerBound]
            guard let close = matchingInnerRuleBrace(in: rule, from: start.lowerBound) else {
                output += rule[start.lowerBound...]
                break
            }
            let contentStart = rule.index(after: start.lowerBound)
            let inner = String(rule[contentStart..<close])
            if let substituted = string(from: object, rule: inner, variables: variables),
               !substituted.isEmpty {
                output += substituted
                replaced = true
            } else {
                output += rule[start.lowerBound...close]
            }
            index = rule.index(after: close)
        }
        return replaced ? output : nil
    }

    /// Finds the `}` matching the `{` at `openIndex`.  Mirrors
    /// `RuleAnalyzer.chompCodeBalanced`: quotes suppress structural
    /// characters, brackets always nest, braces only nest outside brackets,
    /// and a backslash always escapes the next character.
    private func matchingInnerRuleBrace(
        in text: String,
        from openIndex: String.Index
    ) -> String.Index? {
        var index = openIndex
        var braceDepth = 0
        var bracketDepth = 0
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaped = false
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if character == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            } else if inSingleQuote || inDoubleQuote {
                // Quoted JSONPath literals may contain braces and brackets.
            } else if character == "[" {
                bracketDepth += 1
            } else if character == "]" {
                bracketDepth = max(0, bracketDepth - 1)
            } else if bracketDepth == 0, character == "{" {
                braceDepth += 1
            } else if bracketDepth == 0, character == "}" {
                braceDepth -= 1
                if braceDepth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    private func merge(values: [Any], operation: String) -> Any? {
        switch operation {
        case "||":
            return values.first(where: { !isEmptyValue($0) })
        case "&&":
            var merged: [Any] = []
            for item in values { appendFlattened(item, to: &merged) }
            merged.removeAll { isEmptyValue($0) }
            return merged.isEmpty ? nil : merged
        case "%%":
            guard !values.isEmpty else { return nil }
            let arrays = values.map { arrayValues($0) ?? [$0] }
            let merged = interleave(arrays)
            return merged.isEmpty ? nil : merged
        default:
            return values.first
        }
    }

    private func isEmptyValue(_ value: Any) -> Bool {
        if value is NSNull { return true }
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if let array = value as? [Any] { return array.isEmpty }
        if let dict = value as? [String: Any] { return dict.isEmpty }
        return false
    }

    private func decodeJSONValue(_ value: Any) -> Any? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    // MARK: - List and dictionary projection

    private func rootDictionaryList(from object: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        appendRootDictionaries(object, to: &result)
        return result
    }

    private func appendRootDictionaries(_ value: Any, to output: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            output.append(dict)
            return
        }
        if let array = value as? [Any] {
            for item in array { appendRootDictionaries(item, to: &output) }
            return
        }
        if let array = value as? [[String: Any]] {
            output.append(contentsOf: array)
            return
        }
        if let text = value as? String, let decoded = decodeJSONValue(text) {
            appendRootDictionaries(decoded, to: &output)
        }
    }

    private func dictionaries(from value: Any) -> [[String: Any]] {
        var result: [[String: Any]] = []
        appendDictionaries(value, to: &result)
        return result
    }

    private func appendDictionaries(_ value: Any, to output: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            output.append(dict)
            return
        }
        if let array = value as? [Any] {
            for item in array { appendDictionaries(item, to: &output) }
            return
        }
        if let array = value as? NSArray {
            for item in array { appendDictionaries(item, to: &output) }
            return
        }
        if let text = value as? String, let decoded = decodeJSONValue(text) {
            appendDictionaries(decoded, to: &output)
        }
    }

    private func decodedArray(_ value: Any) -> [Any]? {
        if let array = value as? [Any] { return array }
        if let array = value as? [[String: Any]] { return array.map { $0 as Any } }
        if let array = value as? NSArray { return array.map { $0 } }
        if let text = value as? String, let decoded = decodeJSONValue(text) {
            return decodedArray(decoded)
        }
        return nil
    }

    private func listValues(from value: Any) -> [String] {
        if value is NSNull { return [] }
        if let bridge = value as? LegadoElementsBridge {
            return bridge.elements.compactMap { try? $0.text() }.filter { !$0.isEmpty }
        }
        if let bridge = value as? LegadoElementBridge {
            let text = bridge.text()
            return text.isEmpty ? [] : [text]
        }
        if let element = value as? SwiftSoup.Element {
            let text = (try? element.text()) ?? ""
            return text.isEmpty ? [] : [text]
        }
        if let array = value as? [Any] {
            // `AnalyzeByJSonPath.getStringList` adds every element with
            // `toString()`; it never splits element text on newlines.
            return array.flatMap { listValues(from: $0) }
        }
        if let array = value as? [[String: Any]] {
            return array.flatMap { listValues(from: $0) }
        }
        if let text = value as? String {
            if let decoded = decodeJSONValue(text), !(decoded is String) {
                return listValues(from: decoded)
            }
            return text.isEmpty ? [] : [text]
        }
        let text = stringify(value)
        return text.isEmpty ? [] : [text]
    }

    private func listValuesForPath(from object: Any, path: String, variables: [String: Any]) -> [String] {
        guard let selected = value(from: object, path: path, variables: variables) else { return [] }
        return listValues(from: selected)
    }

    private func interleave(_ arrays: [[Any]]) -> [Any] {
        guard !arrays.isEmpty else { return [] }
        let maxCount = arrays[0].count
        var result: [Any] = []
        for index in 0..<maxCount {
            for array in arrays where index < array.count {
                result.append(array[index])
            }
        }
        return result
    }

    private func applyRemainingRule(_ rule: String, object: Any, variables: [String: Any]) -> Any? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return object }
        return value(from: object, path: trimmed, variables: variables)
    }

    // MARK: - Directives (@put / @get)

    private func extractPutDirectives(from rule: String) -> [(key: String, valueRule: String)] {
        RuleDirectiveParser.putPairs(in: rule)
    }

    private func removePutDirectives(from rule: String) -> String {
        RuleDirectiveParser.removingPuts(from: rule)
    }
    private func replaceGetDirectives(in rule: String) -> String {
        RuleDirectiveParser.replacingGets(in: rule) { stringify(directiveValue(for: $0)) }
    }
    private func directGetDirective(in rule: String) -> (key: String, trailing: String)? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("@get:") else { return nil }
        let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: 5)
        var after = markerEnd
        while after < trimmed.endIndex, trimmed[after].isWhitespace {
            after = trimmed.index(after: after)
        }
        let key: String
        let trailingStart: String.Index
        if after < trimmed.endIndex, trimmed[after] == "{" {
            guard let closing = RuleDirectiveParser.matchingBrace(in: trimmed, from: after) else { return nil }
            key = unquote(String(trimmed[trimmed.index(after: after)..<closing])
                .trimmingCharacters(in: .whitespacesAndNewlines))
            trailingStart = trimmed.index(after: closing)
        } else {
            var cursor = after
            while cursor < trimmed.endIndex, isBareDirectiveKeyCharacter(trimmed[cursor]) {
                cursor = trimmed.index(after: cursor)
            }
            key = unquote(String(trimmed[after..<cursor])
                .trimmingCharacters(in: .whitespacesAndNewlines))
            trailingStart = cursor
        }
        guard !key.isEmpty else { return nil }
        let trailing = String(trimmed[trailingStart...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // `@js:`, `<js>` and `@text` style suffixes continue the rule;
        // they are not literal text appended to the stored value.
        if trailing.hasPrefix("@") || trailing.hasPrefix("<js>") { return nil }
        return (key, trailing)
    }

    /// Applies a leading `@get` directive.  An empty suffix returns the stored
    /// value unchanged (preserving native arrays/objects), a `##` suffix runs
    /// the regex transform, and any other suffix is literal text such as
    /// `/book/1` or `?token=@get:{token}`.
    private func resolvedDirectGet(_ direct: (key: String, trailing: String)) -> Any {
        let stored = directiveValue(for: direct.key)
        if direct.trailing.isEmpty {
            return stored
        }
        if direct.trailing.hasPrefix("##") {
            let transforms = splitTransforms(direct.trailing).transforms
            return applyTransforms(transforms, to: stored)
        }
        let suffix = replaceGetDirectives(in: direct.trailing)
        return stringify(stored) + suffix
    }

    private func isBareDirectiveKeyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == "$"
    }

    private func directGetKey(from rule: String) -> String? {
        directGetDirective(in: rule)?.key
    }

    private func directiveValue(for key: String) -> Any {
        if let value = directiveStore.get(key) { return value }
        if let value = executionContext.storedValue(for: key) { return value }
        return NSNull()
    }

    private func applyDirectives(
        from object: Any,
        path: String,
        variables: [String: Any]
    ) -> DirectiveResult {
        for put in extractPutDirectives(from: path) {
            let valueRule = put.valueRule.trimmingCharacters(in: .whitespacesAndNewlines)
            let storedValue: Any
            if valueRule.isEmpty {
                storedValue = object
            } else {
                storedValue = self.value(from: object, path: valueRule, variables: variables) ?? NSNull()
            }
            directiveStore.put(put.key, value: storedValue)
            _ = executionContext.put(storedValue, for: put.key)
        }
        var cleaned = removePutDirectives(from: path)
        let afterPuts = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // A same-rule `@put:{k:...}@get:{k}` is a value template.  Without
        // this branch the substituted value would be re-parsed as a JSON path.
        if afterPuts.lowercased().hasPrefix("@get:"),
           let direct = directGetDirective(in: afterPuts) {
            return .value(resolvedDirectGet(direct))
        }
        cleaned = replaceGetDirectives(in: cleaned)
        return .path(cleaned)
    }

    // MARK: - Path normalization and traversal

    private func valueForSinglePath(from object: Any, path: String) -> Any? {
        let normalized = normalize(path)
        guard !normalized.isEmpty else { return object }
        return walk(object, parts: tokenize(normalized), index: 0)
    }

    private func normalize(_ rule: String) -> String {
        var output = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.lowercased().hasPrefix("@json:") {
            output = String(output.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if output.hasPrefix("$..") {
            output.removeFirst()
            return replacingLastTopLevelAt(in: output)
        }
        if output.hasPrefix("$.") {
            output.removeFirst(2)
        } else if output.hasPrefix("$") {
            output.removeFirst()
        }
        if output.lowercased().hasPrefix("@json:") {
            output = String(output.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if output.hasPrefix("$..") {
            output.removeFirst()
        } else if output.hasPrefix("$.") {
            output.removeFirst(2)
        } else if output.hasPrefix("$") {
            output.removeFirst()
        }
        if output.hasPrefix("@.") {
            output.removeFirst(2)
        } else if output.hasPrefix("@") {
            output.removeFirst()
        }
        if !output.contains("[?"), !output.contains("(") {
            output = replacingLastTopLevelAt(in: output)
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }


    /// Replaces the last `@` separator that is outside quoted keys and
    /// bracket/function expressions. Keys such as `['a@b']` must survive
    /// normalization unchanged.
    private func replacingLastTopLevelAt(in text: String) -> String {
        var lastAt: String.Index?
        var index = text.startIndex
        var quote: Character?
        var escaped = false
        var bracketDepth = 0
        var parenDepth = 0
        while index < text.endIndex {
            let character = text[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else {
                switch character {
                case "[": bracketDepth += 1
                case "]": bracketDepth = max(0, bracketDepth - 1)
                case "(": parenDepth += 1
                case ")": parenDepth = max(0, parenDepth - 1)
                default: break
                }
                if character == "@", bracketDepth == 0, parenDepth == 0 {
                    lastAt = index
                }
            }
            index = text.index(after: index)
        }
        guard let at = lastAt, at != text.startIndex else { return text }
        var output = text
        output.replaceSubrange(at...at, with: ".")
        return output
    }
    private func tokenize(_ path: String) -> [String] {
        var parts: [String] = []
        var buffer = ""
        var index = path.startIndex
        var quote: Character?
        var escaped = false
        var parenDepth = 0
        func flush() {
            let value = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { parts.append(value) }
            buffer.removeAll(keepingCapacity: true)
        }
        while index < path.endIndex {
            let character = path[index]
            if character == "[" {
                flush()
                var depth = 1
                var bracketQuote: Character?
                var bracketEscaped = false
                var cursor = path.index(after: index)
                var token = ""
                while cursor < path.endIndex, depth > 0 {
                    let current = path[cursor]
                    if let activeQuote = bracketQuote {
                        token.append(current)
                        if bracketEscaped {
                            bracketEscaped = false
                        } else if current == "\\" {
                            bracketEscaped = true
                        } else if current == activeQuote {
                            bracketQuote = nil
                        }
                    } else if current == "\"" || current == "'" {
                        bracketQuote = current
                        token.append(current)
                    } else if current == "[" {
                        depth += 1
                        token.append(current)
                    } else if current == "]" {
                        depth -= 1
                        if depth > 0 { token.append(current) }
                    } else {
                        token.append(current)
                    }
                    cursor = path.index(after: cursor)
                }
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    // Keep quotes and commas intact; walk() interprets union
                    // lists and quoted keys with their original delimiters.
                    parts.append(trimmed)
                }
                index = cursor
                continue
            }
            if let activeQuote = quote {
                buffer.append(character)
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
                index = path.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                buffer.append(character)
                index = path.index(after: index)
                continue
            }
            if character == "(" {
                parenDepth += 1
                buffer.append(character)
                index = path.index(after: index)
                continue
            }
            if character == ")" {
                parenDepth = max(0, parenDepth - 1)
                buffer.append(character)
                index = path.index(after: index)
                continue
            }
            if (character == "." || character == "/"), parenDepth == 0 {
                flush()
                if character == "." {
                    let next = path.index(after: index)
                    if next < path.endIndex, path[next] == "." {
                        parts.append("**")
                        index = path.index(after: next)
                        continue
                    }
                }
                index = path.index(after: index)
                continue
            }
            buffer.append(character)
            index = path.index(after: index)
        }
        flush()
        return parts
    }

    private func walk(
        _ current: Any,
        parts: [String],
        index: Int,
        mapMemberOverArrays: Bool = true
    ) -> Any? {
        guard index < parts.count else { return current }
        let part = parts[index]

        var node = current
        if let text = node as? String,
           text.hasPrefix("{") || text.hasPrefix("["),
           let decoded = decodeJSONValue(text) {
            node = decoded
        }

        if let call = parseFunctionCall(part) {
            guard let transformed = applyFunction(name: call.name, arguments: call.arguments, to: node) else {
                return nil
            }
            return walk(
                transformed,
                parts: parts,
                index: index + 1,
                mapMemberOverArrays: true
            )
        }

        if let union = unionSegments(part) {
            var collected: [Any] = []
            let remaining = Array(parts[(index + 1)...])
            for segment in union {
                guard !segment.isEmpty else { continue }
                if let resolved = walk(
                    node,
                    parts: [segment] + remaining,
                    index: 0,
                    mapMemberOverArrays: mapMemberOverArrays
                ) {
                    var items: [Any] = []
                    appendFlattened(resolved, to: &items)
                    // rjpath UnionSelector applies distinct(); keep the first
                    // occurrence so later stages see one copy per node.
                    for item in items where !collected.contains(where: { rjEqualsStrict($0, item) }) {
                        collected.append(item)
                    }
                }
            }
            return collected.isEmpty ? nil : collected
        }

        if part == "**" {
            var matches: [Any] = []
            // Jayway's deep scan applies the remaining path at the current
            // node and then at every descendant.  This extractor additionally
            // maps a bare member step over array elements so sources like
            // `$.data.groups.books.title` work; applying that shorthand while
            // scanning descendants would emit every nested match twice
            // (`$..name` -> A,B,A,B).  Only the first remainder step runs with
            // the shorthand disabled; once that step has been consumed
            // (key/filter/slice/index), later steps must map over arrays again,
            // otherwise `$..list[?(@.x)].name` loses the property lookup.
            // The descendant visit then produces each nested match exactly
            // once, matching Jayway.
            if let direct = walk(
                node,
                parts: parts,
                index: index + 1,
                mapMemberOverArrays: false
            ) {
                appendFlattened(direct, to: &matches)
            }
            for child in children(of: node) {
                if let nested = walk(
                    child,
                    parts: parts,
                    index: index,
                    mapMemberOverArrays: mapMemberOverArrays
                ) {
                    appendFlattened(nested, to: &matches)
                }
            }
            return matches.isEmpty ? nil : matches
        }

        if part.hasPrefix("?(") && part.hasSuffix(")") {
            let expression = String(part.dropFirst(2).dropLast())
            if let array = arrayValues(node) {
                let filtered = array.filter { matchesFilterExpression($0, expression: expression) }
                return walk(
                    filtered,
                    parts: parts,
                    index: index + 1,
                    mapMemberOverArrays: true
                )
            }
            if let dictionary = node as? [String: Any] {
                // rjpath FilterSelector on a JsonObject keeps only entries
                // whose value is itself an object. Swift dictionaries have no
                // stable order, so sort keys to keep output deterministic.
                let filtered = dictionary.keys.sorted().compactMap { key -> Any? in
                    guard let value = dictionary[key], value is [String: Any],
                          matchesFilterExpression(value, expression: expression) else {
                        return nil
                    }
                    return value
                }
                return walk(
                    filtered,
                    parts: parts,
                    index: index + 1,
                    mapMemberOverArrays: true
                )
            }
            return nil
        }

        if let array = arrayValues(node), !isQuotedPathPart(part), part.contains(":") {
            let sliceParts = part.components(separatedBy: ":")
            if sliceParts.count == 2 || sliceParts.count == 3 {
                let startRaw = sliceParts[0].trimmingCharacters(in: .whitespaces)
                let endRaw = sliceParts[1].trimmingCharacters(in: .whitespaces)
                let stepRaw = sliceParts.count == 3 ? sliceParts[2].trimmingCharacters(in: .whitespaces) : ""
                let startValue = startRaw.isEmpty ? nil : Int(startRaw)
                let endValue = endRaw.isEmpty ? nil : Int(endRaw)
                let stepValue = stepRaw.isEmpty ? nil : Int(stepRaw)
                let partsAreNumeric = (startRaw.isEmpty || startValue != nil)
                    && (endRaw.isEmpty || endValue != nil)
                    && (stepRaw.isEmpty || stepValue != nil)
                if partsAreNumeric {
                    let step = stepValue ?? 1
                    guard step != 0 else { return nil }
                    let count = array.count
                    var indices: [Int] = []
                    if step > 0 {
                        var cursor = startValue ?? 0
                        if cursor < 0 { cursor += count }
                        var limit = endValue ?? count
                        if limit < 0 { limit += count }
                        while cursor < limit && cursor < count {
                            if cursor >= 0 { indices.append(cursor) }
                            cursor += step
                        }
                    } else {
                        var cursor = startValue ?? (count - 1)
                        if cursor < 0 { cursor += count }
                        // rjpath keeps the original `end` value for the
                        // negative-step loop condition (no size adjustment).
                        let limit = endValue ?? -1
                        while cursor > limit && cursor >= 0 {
                            if cursor < count { indices.append(cursor) }
                            cursor += step
                        }
                    }
                    let sliced = indices.map { array[$0] }
                    return walk(
                        sliced,
                        parts: parts,
                        index: index + 1,
                        mapMemberOverArrays: true
                    )
                }
            }
        }

        if let dictionary = node as? [String: Any] {
            if part == "*" {
                var flattened: [Any] = []
                for value in dictionary.values {
                    if let subArray = arrayValues(value) {
                        flattened.append(contentsOf: subArray)
                    } else {
                        flattened.append(value)
                    }
                }
                return walk(
                    flattened,
                    parts: parts,
                    index: index + 1,
                    mapMemberOverArrays: true
                )
            }
            guard let value = lookup(dictionary, key: unquoteKey(part)) else { return nil }
            return walk(
                value,
                parts: parts,
                index: index + 1,
                mapMemberOverArrays: true
            )
        }

        if let array = arrayValues(node) {
            if part == "*" {
                let mapped = array.compactMap {
                    walk(
                        $0,
                        parts: parts,
                        index: index + 1,
                        mapMemberOverArrays: true
                    )
                }
                if mapped.isEmpty { return nil }
                var flattened: [Any] = []
                mapped.forEach { appendFlattened($0, to: &flattened) }
                return flattened.count == 1 ? flattened[0] : flattened
            }
            if let number = Int(unquoteKey(part)) {
                let resolved = number < 0 ? array.count + number : number
                guard array.indices.contains(resolved) else { return nil }
                return walk(
                    array[resolved],
                    parts: parts,
                    index: index + 1,
                    mapMemberOverArrays: true
                )
            }
            guard mapMemberOverArrays else { return nil }
            let mapped = array.compactMap {
                walk($0, parts: parts, index: index, mapMemberOverArrays: mapMemberOverArrays)
            }
            if mapped.isEmpty { return nil }
            var flattened: [Any] = []
            mapped.forEach { appendFlattened($0, to: &flattened) }
            return flattened.count == 1 ? flattened[0] : flattened
        }
        return nil
    }

    private func unquoteKey(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              let first = trimmed.first,
              let last = trimmed.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return trimmed
        }
        var inner = String(trimmed.dropFirst().dropLast())
        inner = inner.replacingOccurrences(of: "\\\\", with: "\\")
        inner = inner.replacingOccurrences(of: "\\" + String(first), with: String(first))
        return inner
    }

    private func splitTopLevelCommas(_ text: String) -> [String] {
        var output: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0
        for character in text {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                continue
            }
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                continue
            }
            switch character {
            case "(": parenDepth += 1
            case ")": parenDepth = max(0, parenDepth - 1)
            case "[": bracketDepth += 1
            case "]": bracketDepth = max(0, bracketDepth - 1)
            case "{": braceDepth += 1
            case "}": braceDepth = max(0, braceDepth - 1)
            default: break
            }
            if character == ",", parenDepth == 0, bracketDepth == 0, braceDepth == 0 {
                output.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                continue
            }
            current.append(character)
        }
        output.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return output
    }

    private func unionSegments(_ part: String) -> [String]? {
        guard part.contains(","), !part.hasPrefix("?(") else { return nil }
        guard !looksLikeNumericSlice(part) else { return nil }
        let pieces = splitTopLevelCommas(part)
        guard pieces.count > 1 else { return nil }
        return pieces
    }

    private func looksLikeNumericSlice(_ part: String) -> Bool {
        guard part.contains(":"), !isQuotedPathPart(part) else { return false }
        let pieces = part.components(separatedBy: ":")
        guard pieces.count == 2 || pieces.count == 3 else { return false }
        return pieces.allSatisfy { piece in
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty || Int(trimmed) != nil
        }
    }

    private func isQuotedPathPart(_ part: String) -> Bool {
        let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let first = trimmed.first, let last = trimmed.last else {
            return false
        }
        return (first == "'" && last == "'") || (first == "\"" && last == "\"")
    }

    private func parseFunctionCall(
        _ rawPart: String,
        unquoteArguments: Bool = true
    ) -> (name: String, arguments: [String])? {
        let part = rawPart.trimmingCharacters(in: .whitespacesAndNewlines)
        guard part.hasSuffix(")"), let open = part.firstIndex(of: "(") else { return nil }
        let name = String(part[..<open]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let supported = [
            "length", "count", "match", "search", "value",
            // Project extensions:
            "size", "min", "max", "sum", "avg", "keys", "first", "last",
            "concat", "append", "index"
        ]
        guard supported.contains(name) else { return nil }
        let argStart = part.index(after: open)
        let argEnd = part.index(before: part.endIndex)
        guard argStart <= argEnd else { return (name, []) }
        let argText = String(part[argStart..<argEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !argText.isEmpty else { return (name, []) }
        let arguments = splitTopLevelCommas(argText).map { piece -> String in
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            return unquoteArguments ? unquoteKey(trimmed) : trimmed
        }
        return (name, arguments)
    }

    private func applyFunction(name: String, arguments: [String], to node: Any) -> Any? {
        switch name {
        case "length":
            return sizeOf(node) ?? 0
        case "size":
            return sizeOf(node)
        case "count":
            if node is String || node is NSNumber || node is Bool || node is NSNull { return 1 }
            if let array = arrayValues(node) { return array.count }
            if let dictionary = node as? [String: Any] { return dictionary.count }
            return 1
        case "value":
            return node
        case "match":
            if arguments.count >= 2 {
                return regexMatches(primitiveContent(arguments[0]), expression: arguments[1])
            }
            guard let pattern = arguments.first else { return false }
            return rawRegexContains(stringify(node), pattern: pattern)
        case "search":
            if arguments.count >= 2 {
                return primitiveContent(arguments[0]).contains(arguments[1])
            }
            guard let needle = arguments.first else { return false }
            return stringify(node).contains(needle)
        case "keys":
            guard let dictionary = node as? [String: Any] else { return nil }
            return Array(dictionary.keys)
        case "first":
            return arrayValues(node)?.first
        case "last":
            return arrayValues(node)?.last
        case "min", "max", "sum", "avg":
            guard let array = arrayValues(node) else { return nil }
            let numbers = array.compactMap { numericDouble($0) }
            guard numbers.count == array.count, !numbers.isEmpty else { return nil }
            switch name {
            case "min": return numbers.min()
            case "max": return numbers.max()
            case "sum": return numbers.reduce(0, +)
            default: return numbers.reduce(0, +) / Double(numbers.count)
            }
        case "concat", "append":
            let argument = arguments.first ?? ""
            if let array = arrayValues(node) { return array + [argument as Any] }
            if let text = node as? String { return text + argument }
            return nil
        case "index":
            guard let array = arrayValues(node), let argument = arguments.first else { return nil }
            return array.firstIndex { literalEquals($0, .string(argument)) }
        default:
            return nil
        }
    }

    private func sizeOf(_ value: Any) -> Int? {
        if let array = arrayValues(value) { return array.count }
        if let dictionary = value as? [String: Any] { return dictionary.count }
        if let text = value as? String { return text.utf16.count }
        return nil
    }

    private func numericDouble(_ value: Any) -> Double? {
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" { return nil }
            return number.doubleValue
        }
        if let text = value as? String {
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private func boolValue(_ value: Any) -> Bool? {
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" { return number.boolValue }
            return nil
        }
        if let boolean = value as? Bool { return boolean }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true": return true
            case "false": return false
            default: return nil
            }
        }
        return nil
    }

    private func parseFilterLiteral(_ raw: String) -> FilterLiteral {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .string("") }
        if text.count >= 2,
           let first = text.first,
           let last = text.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return .string(unescapeQuoted(String(text.dropFirst().dropLast())))
        }
        // rjpath does not special-case `null`: an unquoted `null` is the
        // literal string "null", so `@.missing == null` stays false.
        switch text.lowercased() {
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: break
        }
        if text.hasPrefix("["), text.hasSuffix("]") {
            let inner = String(text.dropFirst().dropLast())
            let pieces = splitTopLevelCommas(inner).filter { !$0.isEmpty }
            return .array(pieces.map { parseFilterLiteral($0) })
        }
        if let number = Double(text) { return .number(number) }
        return .string(text)
    }

    private func unescapeQuoted(_ value: String) -> String {
        var output = ""
        var escaped = false
        for character in value {
            if escaped {
                switch character {
                case "n": output.append("\n")
                case "t": output.append("\t")
                case "r": output.append("\r")
                default: output.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                output.append(character)
            }
        }
        if escaped { output.append("\\") }
        return output
    }

    private func literalEquals(_ actual: Any, _ literal: FilterLiteral) -> Bool {
        switch literal {
        case .bool(let expected):
            if let boolean = boolValue(actual) { return boolean == expected }
            return false
        case .number(let expected):
            if let number = numericDouble(actual) { return number == expected }
            return false
        case .string(let expected):
            if let boolean = boolValue(actual), isBooleanValue(actual) {
                return (boolean ? "true" : "false") == expected.lowercased()
            }
            return stringify(actual) == expected
        case .array(let items):
            guard let array = arrayValues(actual), array.count == items.count else { return false }
            return zip(array, items).allSatisfy { literalEquals($0.0, $0.1) }
        }
    }

    private func isBooleanValue(_ value: Any) -> Bool {
        if let number = value as? NSNumber {
            return String(cString: number.objCType) == "c"
        }
        return value is Bool
    }

    /// rjpath `PropertyValueExpression` performs an exact key lookup; no
    /// case-insensitive fallback is allowed here.
    private func lookup(_ dictionary: [String: Any], key: String) -> Any? {
        dictionary[key]
    }

    private func children(of value: Any) -> [Any] {
        if let dictionary = value as? [String: Any] { return Array(dictionary.values) }
        if let array = arrayValues(value) { return array }
        return []
    }

    private func arrayValues(_ value: Any) -> [Any]? {
        if let array = value as? [Any] { return array }
        if let array = value as? [[String: Any]] { return array.map { $0 as Any } }
        if let array = value as? NSArray { return array.map { $0 } }
        if let text = value as? String, let decoded = decodeJSONValue(text) {
            return arrayValues(decoded)
        }
        return nil
    }

    private func appendFlattened(_ value: Any, to output: inout [Any]) {
        if let array = value as? [Any] {
            array.forEach { appendFlattened($0, to: &output) }
        } else {
            output.append(value)
        }
    }

    // MARK: - Filters

    private func matchesFilterExpression(_ value: Any, expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let orParts = splitLogical(trimmed, separator: "||")
        if orParts.count > 1 {
            return orParts.contains { matchesFilterExpression(value, expression: $0) }
        }
        let andParts = splitLogical(trimmed, separator: "&&")
        if andParts.count > 1 {
            return andParts.allSatisfy { matchesFilterExpression(value, expression: $0) }
        }
        if let inner = stripOuterParentheses(trimmed) {
            return matchesFilterExpression(value, expression: inner)
        }
        guard let clause = parseFilterClause(trimmed) else { return false }
        return matchesClause(value, clause: clause)
    }

    private func splitLogical(_ expression: String, separator: String) -> [String] {
        guard !separator.isEmpty else { return [expression] }
        var output: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var bracketDepth = 0
        var parenDepth = 0
        var braceDepth = 0
        var inRegex = false
        var index = expression.startIndex
        while index < expression.endIndex {
            let character = expression[index]
            if escaped {
                current.append(character)
                escaped = false
                index = expression.index(after: index)
                continue
            }
            if character == "\\" {
                current.append(character)
                escaped = true
                index = expression.index(after: index)
                continue
            }
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote { quote = nil }
                index = expression.index(after: index)
                continue
            }
            if character == "\"" || character == "'" {
                quote = character
                current.append(character)
                index = expression.index(after: index)
                continue
            }
            if character == "/" {
                if inRegex {
                    inRegex = false
                } else {
                    let previous = current.trimmingCharacters(in: .whitespacesAndNewlines).last
                    if previous == "~" { inRegex = true }
                }
                current.append(character)
                index = expression.index(after: index)
                continue
            }
            switch character {
            case "[": bracketDepth += 1
            case "]": bracketDepth = max(0, bracketDepth - 1)
            case "(": parenDepth += 1
            case ")": parenDepth = max(0, parenDepth - 1)
            case "{": braceDepth += 1
            case "}": braceDepth = max(0, braceDepth - 1)
            default: break
            }
            if !inRegex, bracketDepth == 0, parenDepth == 0, braceDepth == 0,
               expression[index...].hasPrefix(separator) {
                output.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current = ""
                index = expression.index(index, offsetBy: separator.count)
                continue
            }
            current.append(character)
            index = expression.index(after: index)
        }
        output.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return output
    }

    /// Strips one pair of outer parentheses only when they enclose the whole
    /// expression; mirrors rjpath parseComparisonExpression's grouping branch.
    private func stripOuterParentheses(_ expression: String) -> String? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.hasPrefix("("), trimmed.hasSuffix(")") else {
            return nil
        }
        var depth = 0
        var quote: Character?
        var escaped = false
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0, trimmed.index(after: index) != trimmed.endIndex {
                    return nil
                }
            }
            index = trimmed.index(after: index)
        }
        guard depth == 0 else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }

    private func parseFilterClause(_ expression: String) -> FilterClause? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let found = firstTopLevelFilterOperator(in: trimmed) else {
            return FilterClause(path: trimmed, op: nil, expected: nil)
        }
        let path = String(trimmed[..<found.range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = String(trimmed[found.range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return FilterClause(path: path, op: found.op, expected: expected)
    }

    private func firstTopLevelFilterOperator(
        in expression: String
    ) -> (op: String, range: Range<String.Index>)? {
        var quote: Character?
        var escaped = false
        var bracketDepth = 0
        var parenDepth = 0
        var braceDepth = 0
        var index = expression.startIndex
        while index < expression.endIndex {
            let character = expression[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else {
                switch character {
                case "[": bracketDepth += 1
                case "]": bracketDepth = max(0, bracketDepth - 1)
                case "(": parenDepth += 1
                case ")": parenDepth = max(0, parenDepth - 1)
                case "{": braceDepth += 1
                case "}": braceDepth = max(0, braceDepth - 1)
                default: break
                }
                if bracketDepth == 0, parenDepth == 0, braceDepth == 0 {
                    for op in ["=~", "!=", "==", ">=", "<=", "=", ">", "<"] {
                        if expression[index...].hasPrefix(op) {
                            let end = expression.index(index, offsetBy: op.count)
                            return (op, index..<end)
                        }
                    }
                    // Jayway word operators. They are only recognized when
                    // surrounded by whitespace (or at the expression edge), so
                    // property names such as `index`, `sizeHint`, or `inside`
                    // never turn into operators.
                    for op in ["subsetof", "noneof", "contains", "exists", "anyof", "empty", "size", "nin", "in"] {
                        guard expression[index...].hasPrefix(op) else { continue }
                        let beforeOK = index == expression.startIndex
                            || expression[expression.index(before: index)].isWhitespace
                        let end = expression.index(index, offsetBy: op.count)
                        let afterOK = end == expression.endIndex
                            || expression[end].isWhitespace
                            || expression[end] == "["
                        if beforeOK, afterOK {
                            return (op, index..<end)
                        }
                    }
                }
            }
            index = expression.index(after: index)
        }
        return nil
    }

    private func matchesClause(_ value: Any, clause: FilterClause) -> Bool {
        let expression = clause.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let op = clause.op, let expected = clause.expected else {
            return matchesBareFilter(value, expression: expression)
        }
        let lhs = evaluateFilterValue(expression, node: value) ?? NSNull()
        let rhs = evaluateFilterValue(expected, node: value) ?? NSNull()
        switch op {
        case "=~":
            // Project extension: slash-delimited regex with optional flags.
            return regexMatches(primitiveContent(lhs), expression: unquote(expected))
        case "==", "=":
            return rjEquals(lhs, rhs)
        case "!=":
            // rjpath NotEquals compares JsonElement values directly, without
            // the numeric/boolean coercion used by Equals.
            return !rjEqualsStrict(lhs, rhs)
        case ">":
            if isPrimitiveJSON(lhs), isPrimitiveJSON(rhs) {
                return comparePrimitiveValues(lhs, rhs) > 0
            }
            guard let comparison = rjCompare(lhs, rhs) else { return false }
            return comparison > 0
        case "<":
            if isPrimitiveJSON(lhs), isPrimitiveJSON(rhs) {
                return comparePrimitiveValues(lhs, rhs) < 0
            }
            guard let comparison = rjCompare(lhs, rhs) else { return false }
            return comparison < 0
        case ">=":
            if rjEqualsStrict(lhs, rhs) { return true }
            guard let comparison = rjCompare(lhs, rhs) else { return false }
            return comparison >= 0
        case "<=":
            if rjEqualsStrict(lhs, rhs) { return true }
            guard let comparison = rjCompare(lhs, rhs) else { return false }
            return comparison <= 0
        case "in":
            guard let values = arrayValues(rhs) else { return false }
            return values.contains { rjEquals(lhs, $0) }
        case "nin":
            guard let values = arrayValues(rhs) else { return true }
            return !values.contains { rjEquals(lhs, $0) }
        case "subsetof":
            guard let left = arrayValues(lhs), let right = arrayValues(rhs) else { return false }
            return left.allSatisfy { item in right.contains { rjEquals(item, $0) } }
        case "anyof":
            guard let left = arrayValues(lhs), let right = arrayValues(rhs) else { return false }
            return left.contains { item in right.contains { rjEquals(item, $0) } }
        case "noneof":
            guard let left = arrayValues(lhs), let right = arrayValues(rhs) else { return true }
            return !left.contains { item in right.contains { rjEquals(item, $0) } }
        case "contains":
            return filterContains(lhs, rhs)
        case "size":
            guard let size = filterSize(lhs), let expectedSize = numericDouble(rhs) else { return false }
            return Double(size) == expectedSize
        case "empty":
            let isEmpty = isEmptyValue(lhs)
            if let expectedEmpty = boolValue(rhs) { return isEmpty == expectedEmpty }
            return isEmpty
        case "exists":
            let exists = !(lhs is NSNull)
            if let expectedExists = boolValue(rhs) { return exists == expectedExists }
            return exists
        default:
            return false
        }
    }

    /// Jayway `contains` semantics: substring match for strings, membership
    /// for arrays, and key membership for objects.
    private func filterContains(_ container: Any, _ needle: Any) -> Bool {
        if let text = container as? String {
            return text.contains(primitiveContent(needle))
        }
        if let array = arrayValues(container) {
            return array.contains { rjEquals($0, needle) }
        }
        if let dictionary = container as? [String: Any] {
            return dictionary.keys.contains(primitiveContent(needle))
        }
        return false
    }

    /// Jayway `size` operand: UTF-16 length for strings (matching Kotlin's
    /// String.length), element count for arrays, and key count for objects.
    private func filterSize(_ value: Any) -> Int? {
        if let text = value as? String { return text.utf16.count }
        if let array = arrayValues(value) { return array.count }
        if let dictionary = value as? [String: Any] { return dictionary.count }
        return nil
    }

    /// rjpath `parseFilterExpression` fallback: property truthiness, `@`,
    /// function filters, and string-value filters.
    private func matchesBareFilter(_ value: Any, expression: String) -> Bool {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let call = parseFunctionCall(trimmed, unquoteArguments: false) {
            let arguments = call.arguments.map { evaluateFilterValue($0, node: value) ?? NSNull() }
            guard let result = applyFilterFunction(name: call.name, arguments: arguments) else {
                return false
            }
            return filterTruthy(result)
        }
        if trimmed.hasPrefix("@.") {
            let actual = filterPropertyValue(value, name: String(trimmed.dropFirst(2)))
            return filterTruthy(actual)
        }
        if trimmed == "@" { return true }
        guard isPrimitiveJSON(value) else { return false }
        return primitiveContent(value) == unquote(trimmed)
    }

    /// Evaluate a value expression inside a filter (`@.field`, `@`,
    /// `length(@.field)`, `match(@.title,'x')`, literals).
    private func evaluateFilterValue(_ raw: String, node: Any) -> Any? {
        let expression = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else { return nil }
        if expression.hasPrefix("@.") {
            return filterPropertyValue(node, name: String(expression.dropFirst(2)))
        }
        if expression == "@" { return node }
        if let call = parseFunctionCall(expression, unquoteArguments: false) {
            let arguments = call.arguments.map { evaluateFilterValue($0, node: node) ?? NSNull() }
            return applyFilterFunction(name: call.name, arguments: arguments)
        }
        return filterLiteralValue(parseFilterLiteral(expression))
    }

    /// rjpath `PropertyValueExpression`: objects return the property or
    /// JsonNull; every other node type returns the node itself.
    private func filterPropertyValue(_ node: Any, name: String) -> Any {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return node }
        guard let dictionary = node as? [String: Any] else { return node }
        if let direct = dictionary[key] { return direct }
        if key.contains(".") || key.contains("[") {
            if let nested = valueForSinglePath(from: node, path: key) { return nested }
        }
        if let value = lookup(dictionary, key: key) { return value }
        return NSNull()
    }

    private func filterLiteralValue(_ literal: FilterLiteral) -> Any {
        switch literal {
        case .bool(let value): return value
        case .number(let value): return value
        case .string(let value): return value
        case .array(let items): return items.map { filterLiteralValue($0) }
        }
    }

    private func isPrimitiveJSON(_ value: Any) -> Bool {
        if value is NSNull { return false }
        if value is String || value is Bool { return true }
        return value is NSNumber
    }

    private func primitiveContent(_ value: Any) -> String {
        if let text = value as? String { return text }
        // On Apple platforms every Bool bridges to NSNumber and `as? Bool`
        // also succeeds for plain numbers, so NSNumber must be inspected
        // first: objCType == "c" is the only reliable boolean marker.
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" {
                return number.boolValue ? "true" : "false"
            }
            return stringify(number)
        }
        if let boolean = value as? Bool { return boolean ? "true" : "false" }
        return stringify(value)
    }

    /// rjpath `Equals`: numeric coercion first, then boolean, then content.
    private func rjEquals(_ lhs: Any, _ rhs: Any) -> Bool {
        if isPrimitiveJSON(lhs), isPrimitiveJSON(rhs) {
            if let leftNumber = numericDouble(lhs), let rightNumber = numericDouble(rhs) {
                return leftNumber == rightNumber
            }
            if let leftBoolean = boolValue(lhs), let rightBoolean = boolValue(rhs) {
                return leftBoolean == rightBoolean
            }
            return primitiveContent(lhs) == primitiveContent(rhs)
        }
        return rjEqualsStrict(lhs, rhs)
    }

    /// Type-preserving equality used by `!=`, `<=`, `>=` and structural
    /// comparison. Mirrors kotlinx JsonElement equality: numbers are numbers,
    /// strings are strings, booleans are booleans.
    private func rjEqualsStrict(_ lhs: Any, _ rhs: Any) -> Bool {
        if lhs is NSNull || rhs is NSNull {
            return lhs is NSNull && rhs is NSNull
        }
        if isBooleanValue(lhs) || isBooleanValue(rhs) {
            guard isBooleanValue(lhs), isBooleanValue(rhs) else { return false }
            return boolValue(lhs) == boolValue(rhs)
        }
        if let leftNumber = lhs as? NSNumber {
            guard let rightNumber = rhs as? NSNumber else { return false }
            return leftNumber.doubleValue == rightNumber.doubleValue
        }
        if let leftText = lhs as? String {
            guard let rightText = rhs as? String else { return false }
            return leftText == rightText
        }
        if let leftArray = lhs as? [Any] {
            guard let rightArray = rhs as? [Any], leftArray.count == rightArray.count else {
                return false
            }
            return zip(leftArray, rightArray).allSatisfy { rjEqualsStrict($0.0, $0.1) }
        }
        if let leftObject = lhs as? [String: Any] {
            guard let rightObject = rhs as? [String: Any],
                  leftObject.count == rightObject.count else { return false }
            for (key, leftValue) in leftObject {
                guard let rightValue = rightObject[key], rjEqualsStrict(leftValue, rightValue) else {
                    return false
                }
            }
            return true
        }
        return false
    }

    /// `<` / `>` primitive branch: both numbers, else both booleans, else
    /// lexicographic string content.
    private func comparePrimitiveValues(_ lhs: Any, _ rhs: Any) -> Int {
        if let leftNumber = numericDouble(lhs), let rightNumber = numericDouble(rhs) {
            return leftNumber < rightNumber ? -1 : (leftNumber > rightNumber ? 1 : 0)
        }
        if let leftBoolean = boolValue(lhs), let rightBoolean = boolValue(rhs) {
            if leftBoolean == rightBoolean { return 0 }
            return leftBoolean ? 1 : -1
        }
        let leftText = primitiveContent(lhs)
        let rightText = primitiveContent(rhs)
        return leftText < rightText ? -1 : (leftText > rightText ? 1 : 0)
    }

    /// rjpath `compareJsonElements` used by `<=`, `>=` and by `<` / `>` for
    /// non-primitive operands. Note the OR-number rule: if either side parses
    /// as a number, the other side defaults to 0.0.
    private func rjCompare(_ lhs: Any, _ rhs: Any) -> Int? {
        let leftNull = lhs is NSNull
        let rightNull = rhs is NSNull
        if leftNull || rightNull {
            return (leftNull && rightNull) ? 0 : nil
        }
        if isPrimitiveJSON(lhs), isPrimitiveJSON(rhs) {
            let leftNumber = numericDouble(lhs)
            let rightNumber = numericDouble(rhs)
            if leftNumber != nil || rightNumber != nil {
                let leftValue = leftNumber ?? 0
                let rightValue = rightNumber ?? 0
                return leftValue < rightValue ? -1 : (leftValue > rightValue ? 1 : 0)
            }
            if let leftBoolean = boolValue(lhs), let rightBoolean = boolValue(rhs) {
                if leftBoolean == rightBoolean { return 0 }
                return leftBoolean ? 1 : -1
            }
            let leftText = primitiveContent(lhs)
            let rightText = primitiveContent(rhs)
            return leftText < rightText ? -1 : (leftText > rightText ? 1 : 0)
        }
        if let leftArray = lhs as? [Any], let rightArray = rhs as? [Any] {
            if leftArray.count != rightArray.count {
                return leftArray.count < rightArray.count ? -1 : 1
            }
            for (leftValue, rightValue) in zip(leftArray, rightArray) {
                if let comparison = rjCompare(leftValue, rightValue), comparison != 0 {
                    return comparison
                }
            }
            return 0
        }
        if let leftObject = lhs as? [String: Any], let rightObject = rhs as? [String: Any] {
            if leftObject.count != rightObject.count {
                return leftObject.count < rightObject.count ? -1 : 1
            }
            let leftKeys = leftObject.keys.sorted()
            let rightKeys = rightObject.keys.sorted()
            for (leftKey, rightKey) in zip(leftKeys, rightKeys) where leftKey != rightKey {
                return leftKey < rightKey ? -1 : 1
            }
            for key in leftKeys {
                let leftValue = leftObject[key] ?? NSNull()
                let rightValue = rightObject[key] ?? NSNull()
                if let comparison = rjCompare(leftValue, rightValue), comparison != 0 {
                    return comparison
                }
            }
            return 0
        }
        return nil
    }

    /// FunctionFilterExpression / PropertyFilterExpression truthiness.
    private func filterTruthy(_ value: Any) -> Bool {
        if value is NSNull { return false }
        if let text = value as? String { return !text.isEmpty }
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" { return number.boolValue }
            return number.doubleValue != 0
        }
        if let boolean = value as? Bool { return boolean }
        if let array = arrayValues(value) { return !array.isEmpty }
        if let dictionary = value as? [String: Any] { return !dictionary.isEmpty }
        return false
    }

    /// Official rjpath functions used inside filter expressions.
    private func applyFilterFunction(name: String, arguments: [Any]) -> Any? {
        switch name {
        case "length":
            guard let value = arguments.first else { return 0 }
            // Kotlin String.length counts UTF-16 code units, not graphemes.
            if let text = value as? String { return Double(text.utf16.count) }
            if let array = arrayValues(value) { return Double(array.count) }
            if let dictionary = value as? [String: Any] { return Double(dictionary.count) }
            return 0
        case "count":
            guard let value = arguments.first else { return 1 }
            if value is String || value is NSNumber || value is Bool || value is NSNull {
                return 1
            }
            if let array = arrayValues(value) { return Double(array.count) }
            if let dictionary = value as? [String: Any] { return Double(dictionary.count) }
            return 1
        case "match":
            guard arguments.count >= 2 else { return false }
            return regexMatches(primitiveContent(arguments[0]), expression: primitiveContent(arguments[1]))
        case "search":
            guard arguments.count >= 2 else { return false }
            return primitiveContent(arguments[0]).contains(primitiveContent(arguments[1]))
        case "value":
            return arguments.first ?? NSNull()
        default:
            return nil
        }
    }

    private func rawRegexContains(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func regexMatches(_ text: String, expression: String) -> Bool {
        var pattern = expression
        var options: NSRegularExpression.Options = []
        if expression.hasPrefix("/"),
           let lastSlash = expression.lastIndex(of: "/"),
           lastSlash != expression.startIndex {
            pattern = String(expression[expression.index(after: expression.startIndex)..<lastSlash])
            let flags = String(expression[expression.index(after: lastSlash)...])
            if flags.contains("i") { options.insert(.caseInsensitive) }
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    private func truthy(_ value: Any) -> Bool {
        filterTruthy(value)
    }

    // MARK: - Transforms

    private func splitTransforms(_ rawRule: String) -> (path: String, transforms: [RegexTransform]) {
        let split = RuleTransformParser.split(rawRule)
        return (split.path, split.transform.map { [$0] } ?? [])
    }

    private func applyTransforms(_ transforms: [RegexTransform], to list: [String]) -> [String] {
        guard !transforms.isEmpty else { return list }
        return list.map { item in
            var text = item
            for transform in transforms {
                text = RuleTransformParser.apply(transform, to: text)
            }
            return text
        }
    }

    private func applyTransforms(_ transforms: [RegexTransform], to value: Any) -> Any {
        guard !transforms.isEmpty else { return value }
        if let array = value as? [Any] {
            return array.map { applyTransforms(transforms, to: $0) }
        }
        if let array = value as? [[String: Any]] {
            return array.map { applyTransforms(transforms, to: $0) }
        }
        var text = stringify(value)
        for transform in transforms {
            text = RuleTransformParser.apply(transform, to: text)
        }
        return text
    }

    /// Splits a rule into normal template segments and JavaScript segments.
    ///
    /// Legado's `JS_PATTERN` treats `@js:` anywhere in a rule as the start of a
    /// JavaScript segment, and `<js>...</js>` as an inline script.  A template
    /// such as `{{$.a}},{{$.b}}@js:result.replace(...)` therefore evaluates the
    /// interpolated text first and passes it to the script as `result`.
    private func splitTemplateJSSegments(_ rule: String) -> [SourceSegment] {
        var segments: [SourceSegment] = []
        var remaining = rule

        while !remaining.isEmpty {
            let atRange = remaining.range(of: "@js:")
            let tagRange = remaining.range(of: "<js>")
            let markerStart: String.Index
            let isAtSyntax: Bool
            switch (atRange, tagRange) {
            case let (at?, tag?):
                if at.lowerBound < tag.lowerBound {
                    markerStart = at.lowerBound
                    isAtSyntax = true
                } else {
                    markerStart = tag.lowerBound
                    isAtSyntax = false
                }
            case let (at?, nil):
                markerStart = at.lowerBound
                isAtSyntax = true
            case let (nil, tag?):
                markerStart = tag.lowerBound
                isAtSyntax = false
            case (nil, nil):
                let text = remaining
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.normal(text))
                }
                return segments
            }

            let before = String(remaining[..<markerStart])
            if !before.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.normal(before))
            }

            if isAtSyntax {
                let codeStart = remaining.index(markerStart, offsetBy: 4)
                let tail = String(remaining[codeStart...])
                let nextAt = tail.range(of: "@js:")
                let nextTag = tail.range(of: "<js>")
                let cut: String.Index
                switch (nextAt, nextTag) {
                case let (at?, tag?):
                    cut = min(at.lowerBound, tag.lowerBound)
                case let (at?, nil):
                    cut = at.lowerBound
                case let (nil, tag?):
                    cut = tag.lowerBound
                case (nil, nil):
                    cut = tail.endIndex
                }
                let code = String(tail[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty { segments.append(.js(code)) }
                remaining = String(tail[cut...])
            } else {
                let codeStart = remaining.index(markerStart, offsetBy: 4)
                guard let end = remaining.range(of: "</js>", range: codeStart..<remaining.endIndex) else {
                    let code = String(remaining[codeStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !code.isEmpty { segments.append(.js(code)) }
                    return segments
                }
                let code = String(remaining[codeStart..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty { segments.append(.js(code)) }
                remaining = String(remaining[end.upperBound...])
            }
        }
        return segments
    }

    /// Evaluates a `{{...}}` template together with trailing `@js:` / `<js>`
    /// segments.  The interpolated text becomes `result` for the script, which
    /// is how Legado chains `{{}}` and `@js:` in one rule.
    private func evaluateTemplateSegments(
        _ rule: String,
        item: [String: Any],
        variables: [String: Any]
    ) -> Any? {
        let segments = splitTemplateJSSegments(rule)
        guard !segments.isEmpty else { return nil }
        var current: Any = item
        for segment in segments {
            switch segment {
            case .normal(let text):
                let interpolated = interpolateTemplate(text, item: item, variables: variables)
                let split = splitTransforms(interpolated)
                if split.transforms.isEmpty {
                    current = split.path
                } else {
                    current = applyTransforms(split.transforms, to: split.path)
                }
            case .js(let code):
                guard let next = evaluateRawJS(script: code, object: current, extraVariables: variables) else {
                    return nil
                }
                current = next
            }
        }
        return current
    }

    /// Legado's `makeUpRule` formats JavaScript results as follows: `null` is
    /// skipped, strings are inserted verbatim, integral doubles use `%.0f`,
    /// and everything else uses `toString()`.  `NSNumber` would otherwise
    /// render `2.0` for the integer `2`.
    func stringifyJSResult(_ value: Any) -> String {
        if value is NSNull { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let doubleValue = number.doubleValue
            if doubleValue.isFinite,
               doubleValue.truncatingRemainder(dividingBy: 1) == 0,
               abs(doubleValue) < 1e15 {
                return String(format: "%.0f", doubleValue)
            }
            return number.stringValue
        }
        return stringify(value)
    }
    private func interpolateTemplate(_ template: String, item: [String: Any], variables: [String: Any]) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([^{}]+)\s*\}\}"#) else { return template }
        let mText = NSMutableString(string: template)
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: mText.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let keyRange = match.range(at: 1)
            let fullRange = match.range(at: 0)
            let key = mText.substring(with: keyRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let val: String
            if key.hasPrefix("$.") || key.hasPrefix("@json:") {
                val = (value(from: item, path: key, variables: variables)).map { stringifyJSResult($0) } ?? ""
            } else if let direct = item[key] {
                val = stringifyJSResult(direct)
            } else if let fromPath = value(from: item, path: key, variables: variables) {
                val = stringifyJSResult(fromPath)
            } else if let varVal = variables[key] {
                val = stringifyJSResult(varVal)
            } else if let jsValue = evaluateRawJS(script: key, object: item, extraVariables: variables) {
                // Legado treats `{{...}}` as a JavaScript rule.  Keep the
                // direct-key and JSONPath lookups above for the common
                // `{{key}}` / `{{$.field}}` templates, then evaluate any
                // remaining expression with `result` bound to the item.
                val = stringifyJSResult(jsValue)
            } else {
                val = ""
            }
            mText.replaceCharacters(in: fullRange, with: val)
        }
        return mText as String
    }

    private func unquote(_ value: String) -> String {
        var output = value
        if output.count >= 2,
           let first = output.first,
           let last = output.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            output.removeFirst()
            output.removeLast()
        }
        return output
    }

    private func evaluateJS(
        rule: String,
        object: Any,
        extraVariables: [String: Any]
    ) -> Any? {
        var script = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if script.hasPrefix("<js>") && script.contains("</js>") {
            let start = script.index(script.startIndex, offsetBy: 4)
            let end = script.range(of: "</js>")?.lowerBound ?? script.endIndex
            let rest = String(script[script.range(of: "</js>")!.upperBound...])
            script = String(script[start..<end]) + rest
        }

        var trailingTransform: RuleRegexTransform?
        if script.hasPrefix("##") {
            trailingTransform = RuleTransformParser.transform(
                fromTrailingParts: script.components(separatedBy: "##").dropFirst()
            )
            return RuleTransformParser.apply(trailingTransform, to: stringify(object))
        }

        if script.contains("##") {
            if let lineBreak = script.range(of: "\n##", options: .backwards) {
                let hashStart = script.index(after: lineBreak.lowerBound)
                let regexText = String(script[hashStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                script = String(script[..<lineBreak.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                trailingTransform = RuleTransformParser.transform(
                    fromTrailingParts: regexText.components(separatedBy: "##").dropFirst()
                )
            } else if let hashRange = script.range(of: "##") {
                let regexText = String(script[hashRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = regexText.components(separatedBy: "##").dropFirst()
                if !parts.isEmpty {
                    script = String(script[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    trailingTransform = RuleTransformParser.transform(fromTrailingParts: parts)
                }
            }
        }

        let jsResult = evaluateRawJS(script: script, object: object, extraVariables: extraVariables)
        guard let jsResult else { return nil }
        guard trailingTransform != nil else { return jsResult }
        return RuleTransformParser.apply(trailingTransform, to: stringify(jsResult))
    }

    func evaluateRawJS(
        script: String,
        object: Any,
        extraVariables: [String: Any]
    ) -> Any? {
        let source = extraVariables["source"] as? BookSource
        let runtime = executionContext.jsRuntime(ajaxHandler: { urlText in
            if let source {
                return SynchronousSourceLoader().load(urlText: urlText, source: source)
            }
            return ""
        })

        var convertedObject = object
        let baseStr = (extraVariables["baseUrl"] as? String) ?? ""
        if let elements = object as? [Element] {
            convertedObject = LegadoElementsBridge(elements: elements, baseURL: baseStr)
        } else if let el = object as? Element {
            convertedObject = LegadoElementBridge(element: el, baseURL: baseStr)
        }

        var variables: [String: Any] = [
            "result": convertedObject
        ]

        // Apply extraVariables first so root document and caller context take precedence
        for (k, v) in extraVariables {
            if k != "result" {
                variables[k] = v
            }
        }

        // If extraVariables did not provide html/src, populate from object
        if variables["html"] == nil {
            if let dict = object as? [String: Any] {
                if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    variables["html"] = jsonStr
                    variables["src"] = jsonStr
                }
            } else if JSONSerialization.isValidJSONObject(object) {
                if let data = try? JSONSerialization.data(withJSONObject: object, options: []),
                   let jsonStr = String(data: data, encoding: .utf8) {
                    variables["html"] = jsonStr
                    variables["src"] = jsonStr
                }
            } else {
                let str = stringify(object)
                variables["html"] = str
                variables["src"] = str
            }
        }

        if let dict = object as? [String: Any] {
            // Also expose item keys directly in JS scope if non-colliding
            for (k, v) in dict {
                if variables[k] == nil {
                    variables[k] = v
                }
            }
        }

        let evaluated = runtime.evaluate(script, variables: variables)
        if let jsValue = runtime.context.objectForKeyedSubscript("result") {
            if let bridge = jsValue.toObject() as? LegadoElementsBridge {
                return bridge
            } else if let bridge = jsValue.toObject() as? LegadoElementBridge {
                return bridge
            }
        }
        if case .failure(.javascript) = evaluated, script.contains("return") {
            if case .success(let val) = runtime.evaluate("(function(){\(script)})()", variables: variables) {
                return val
            }
        }
        if case .success(let val) = evaluated {
            return val
        }
        return nil
    }

    func stringify(_ value: Any) -> String {
        if let array = value as? [Any] {
            return array.map { stringify($0) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        }
        if let dict = value as? [String: Any] {
            for key in ["p", "content", "text", "body", "title", "name"] {
                if let v = dict[key] { return stringify(v) }
            }
            // Legado's `getString` calls `toString()` on a map result, so an
            // unknown object must still yield content instead of an empty
            // string.  Sorted keys keep the output deterministic for tests and
            // for `##regex##replacement` transforms applied afterwards.
            if JSONSerialization.isValidJSONObject(dict),
               let data = try? JSONSerialization.data(
                   withJSONObject: dict,
                   options: [.sortedKeys, .fragmentsAllowed]
               ),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
            return ""
        }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text == "<null>" ? "" : text
    }
}
