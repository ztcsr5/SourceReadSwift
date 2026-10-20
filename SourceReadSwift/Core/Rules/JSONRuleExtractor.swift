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

    struct RegexTransform {
        let pattern: String
        let replacement: String
        let replaceFirst: Bool
    }

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
            let text = stringify(extracted)
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
                let interpolated = interpolateTemplate(trimmed, item: item, variables: variables)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if interpolated.hasPrefix("http://") || interpolated.hasPrefix("https://") || interpolated.hasPrefix("/") {
                    let cleanedURL = splitTransforms(interpolated).path
                    if !cleanedURL.isEmpty {
                        return cleanedURL
                    }
                }
                if interpolated.hasPrefix("@js:")
                    || interpolated.hasPrefix("<js>")
                    || interpolated.contains("@js:")
                    || interpolated.contains("<js>")
                    || interpolated.contains("$.")
                    || interpolated.contains("@json:") {
                    if let value = value(from: item, path: interpolated, variables: variables) {
                        let text = stringify(value)
                        if !text.isEmpty { return text }
                    }
                } else if !interpolated.isEmpty {
                    return splitTransforms(interpolated).path
                }
            }
            if let value = value(from: item, path: rule, variables: variables) {
                let text = stringify(value)
                if !text.isEmpty { return text }
            }
        }
        for key in fallbackKeys {
            if let value = item[key] {
                let text = stringify(value)
                if !text.isEmpty { return text }
            }
            let lowerKey = key.lowercased()
            if let matchKey = item.keys.first(where: { $0.lowercased() == lowerKey }),
               let value = item[matchKey] {
                let text = stringify(value)
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
            let stored = directiveValue(for: direct.key)
            let transforms = splitTransforms(direct.trailing).transforms
            return applyTransforms(transforms, to: stored)
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
        return valueForSinglePath(from: object, path: part)
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
            return array.flatMap { listValues(from: $0) }
        }
        if let array = value as? [[String: Any]] {
            return array.flatMap { listValues(from: $0) }
        }
        if let text = value as? String {
            if let decoded = decodeJSONValue(text), !(decoded is String) {
                return listValues(from: decoded)
            }
            return text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
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

    private func directiveSpans(
        in rule: String,
        marker: String
    ) -> [(range: Range<String.Index>, body: String)] {
        var spans: [(range: Range<String.Index>, body: String)] = []
        let lowered = rule.lowercased()
        let loweredMarker = marker.lowercased()
        var searchStart = rule.startIndex
        while searchStart < rule.endIndex,
              let markerRange = lowered.range(of: loweredMarker, range: searchStart..<rule.endIndex) {
            let braceStart = markerRange.upperBound
            guard braceStart < rule.endIndex, rule[braceStart] == "{" else {
                searchStart = braceStart
                continue
            }
            var depth = 0
            var quote: Character?
            var escaped = false
            var cursor = braceStart
            var endIndex: String.Index?
            while cursor < rule.endIndex {
                let character = rule[cursor]
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if let activeQuote = quote {
                    if character == activeQuote { quote = nil }
                } else if character == "\"" || character == "'" {
                    quote = character
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        endIndex = rule.index(after: cursor)
                        break
                    }
                }
                cursor = rule.index(after: cursor)
            }
            guard let end = endIndex else { break }
            let bodyStart = rule.index(after: braceStart)
            let bodyEnd = rule.index(before: end)
            let body = String(rule[bodyStart..<bodyEnd])
            spans.append((markerRange.lowerBound..<end, body))
            searchStart = end
        }
        return spans
    }

    private func extractPutDirectives(from rule: String) -> [(key: String, valueRule: String)] {
        directiveSpans(in: rule, marker: "@put:").compactMap { parsePutBody($0.body) }
    }

    private func removePutDirectives(from rule: String) -> String {
        let spans = directiveSpans(in: rule, marker: "@put:")
        guard !spans.isEmpty else { return rule }
        var output = rule
        for span in spans.reversed() {
            output.removeSubrange(span.range)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsePutBody(_ rawBody: String) -> (key: String, valueRule: String)? {
        let body = rawBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        // directiveSpans strips the outer braces, so re-wrap the body before
        // asking JSONSerialization to parse the key/value pair.
        if let data = ("{" + body + "}").data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let dictionary = object as? [String: Any],
           dictionary.count == 1,
           let pair = dictionary.first {
            return (pair.key, stringify(pair.value))
        }
        if body.hasPrefix("{"),
           let data = body.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           let dictionary = object as? [String: Any],
           dictionary.count == 1,
           let pair = dictionary.first {
            return (pair.key, stringify(pair.value))
        }
        var quote: Character?
        var escaped = false
        var depth = 0
        var separator: String.Index?
        var index = body.startIndex
        while index < body.endIndex {
            let character = body[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" || character == "[" || character == "(" {
                depth += 1
            } else if character == "}" || character == "]" || character == ")" {
                depth = max(0, depth - 1)
            } else if character == ":", depth == 0 {
                separator = index
                break
            }
            index = body.index(after: index)
        }
        if let separator {
            let key = unquote(String(body[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines))
            let valueRule = String(body[body.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return nil }
            return (key, valueRule)
        }
        let key = unquote(body)
        return key.isEmpty ? nil : (key, "")
    }

    private func replaceGetDirectives(in rule: String) -> String {
        var output = ""
        var index = rule.startIndex
        let lowered = rule.lowercased()
        while index < rule.endIndex {
            guard let range = lowered.range(of: "@get:", range: index..<rule.endIndex) else {
                output.append(contentsOf: rule[index...])
                break
            }
            output.append(contentsOf: rule[index..<range.lowerBound])
            let after = range.upperBound
            if after < rule.endIndex, rule[after] == "{" {
                if let closing = matchingBrace(in: rule, from: after) {
                    let bodyStart = rule.index(after: after)
                    let key = unquote(String(rule[bodyStart..<closing]).trimmingCharacters(in: .whitespacesAndNewlines))
                    output.append(stringify(directiveValue(for: key)))
                    index = rule.index(after: closing)
                    continue
                }
            }
            var cursor = after
            while cursor < rule.endIndex {
                let character = rule[cursor]
                if character == "." || character == "/" || character == "[" || character == "@" || character.isWhitespace {
                    break
                }
                cursor = rule.index(after: cursor)
            }
            let key = unquote(String(rule[after..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines))
            output.append(stringify(directiveValue(for: key)))
            index = cursor
        }
        return output
    }

    private func matchingBrace(in text: String, from open: String.Index) -> String.Index? {
        guard open < text.endIndex, text[open] == "{" else { return nil }
        var depth = 0
        var quote: Character?
        var escaped = false
        var cursor = open
        while cursor < text.endIndex {
            let character = text[cursor]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if let activeQuote = quote {
                if character == activeQuote { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 { return cursor }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private func directGetDirective(in rule: String) -> (key: String, trailing: String)? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("@get:") else { return nil }
        let markerEnd = trimmed.index(trimmed.startIndex, offsetBy: 5)
        guard markerEnd < trimmed.endIndex, trimmed[markerEnd] == "{" else { return nil }
        guard let closing = matchingBrace(in: trimmed, from: markerEnd) else { return nil }
        let keyStart = trimmed.index(after: markerEnd)
        let key = unquote(String(trimmed[keyStart..<closing]).trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty else { return nil }
        let trailing = String(trimmed[trimmed.index(after: closing)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trailing.isEmpty || trailing.hasPrefix("##") else { return nil }
        return (key, trailing)
    }

    private func directGetKey(from rule: String) -> String? {
        directGetDirective(in: rule)?.key
    }

    private func directiveValue(for key: String) -> Any {
        if let value = directiveStore.get(key) { return value }
        if let value = executionContext.value(for: key) { return value }
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
            return output
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
        if !output.contains("[?"),
           let atIndex = output.lastIndex(of: "@"),
           atIndex != output.startIndex {
            output.replaceSubrange(atIndex...atIndex, with: ".")
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func tokenize(_ path: String) -> [String] {
        var parts: [String] = []
        var buffer = ""
        var index = path.startIndex
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
                var quote: Character?
                var escaped = false
                var cursor = path.index(after: index)
                var token = ""
                while cursor < path.endIndex, depth > 0 {
                    let current = path[cursor]
                    if let activeQuote = quote {
                        token.append(current)
                        if escaped {
                            escaped = false
                        } else if current == "\\" {
                            escaped = true
                        } else if current == activeQuote {
                            quote = nil
                        }
                    } else if current == "\"" || current == "'" {
                        quote = current
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
                    parts.append(unquote(trimmed))
                }
                index = cursor
                continue
            }
            if character == "." || character == "/" {
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

    private func walk(_ current: Any, parts: [String], index: Int) -> Any? {
        guard index < parts.count else { return current }
        let part = parts[index]

        var node = current
        if let text = node as? String,
           text.hasPrefix("{") || text.hasPrefix("["),
           let decoded = decodeJSONValue(text) {
            node = decoded
        }

        if part == "**" {
            var matches: [Any] = []
            if let direct = walk(node, parts: parts, index: index + 1) {
                appendFlattened(direct, to: &matches)
            }
            for child in children(of: node) {
                if let nested = walk(child, parts: parts, index: index) {
                    appendFlattened(nested, to: &matches)
                }
            }
            return matches.isEmpty ? nil : matches
        }

        if part.hasPrefix("?(") && part.hasSuffix(")") {
            guard let array = arrayValues(node) else { return nil }
            let expression = String(part.dropFirst(2).dropLast())
            let filtered = array.filter { matchesFilterExpression($0, expression: expression) }
            return walk(filtered, parts: parts, index: index + 1)
        }

        if let array = arrayValues(node), part.contains(":") {
            let sliceParts = part.components(separatedBy: ":")
            if sliceParts.count == 2 {
                let count = array.count
                let startRaw = sliceParts[0].trimmingCharacters(in: .whitespaces)
                let endRaw = sliceParts[1].trimmingCharacters(in: .whitespaces)
                let startIndex = startRaw.isEmpty ? 0 : (Int(startRaw) ?? 0)
                let endIndex = endRaw.isEmpty ? count : (Int(endRaw) ?? count)
                let resolvedStart = max(0, min(count, startIndex < 0 ? count + startIndex : startIndex))
                let resolvedEnd = max(0, min(count, endIndex < 0 ? count + endIndex : endIndex))
                if resolvedStart <= resolvedEnd {
                    let sliced = Array(array[resolvedStart..<resolvedEnd])
                    return walk(sliced, parts: parts, index: index + 1)
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
                return walk(flattened, parts: parts, index: index + 1)
            }
            guard let value = lookup(dictionary, key: part) else { return nil }
            return walk(value, parts: parts, index: index + 1)
        }

        if let array = arrayValues(node) {
            if part == "*" {
                let mapped = array.compactMap { walk($0, parts: parts, index: index + 1) }
                if mapped.isEmpty { return nil }
                var flattened: [Any] = []
                mapped.forEach { appendFlattened($0, to: &flattened) }
                return flattened.count == 1 ? flattened[0] : flattened
            }
            if let number = Int(part) {
                let resolved = number < 0 ? array.count + number : number
                guard array.indices.contains(resolved) else { return nil }
                return walk(array[resolved], parts: parts, index: index + 1)
            }
            let mapped = array.compactMap { walk($0, parts: parts, index: index) }
            if mapped.isEmpty { return nil }
            var flattened: [Any] = []
            mapped.forEach { appendFlattened($0, to: &flattened) }
            return flattened.count == 1 ? flattened[0] : flattened
        }
        return nil
    }

    private func lookup(_ dictionary: [String: Any], key: String) -> Any? {
        if let value = dictionary[key] { return value }
        if let value = dictionary[key.lowercased()] { return value }
        if let value = dictionary[key.uppercased()] { return value }
        let lowered = key.lowercased()
        return dictionary.first(where: { $0.key.lowercased() == lowered })?.value
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
                }
            }
            index = expression.index(after: index)
        }
        return nil
    }

    private func matchesClause(_ value: Any, clause: FilterClause) -> Bool {
        var key = clause.path.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("@.") {
            key = String(key.dropFirst(2))
        } else if key == "@" {
            key = ""
        }
        let actual: Any?
        if key.isEmpty {
            actual = value
        } else {
            actual = valueForSinglePath(from: value, path: key)
        }
        guard let actual, !(actual is NSNull) else { return false }
        guard let op = clause.op, let expected = clause.expected else {
            return truthy(actual)
        }
        let lhs = stringify(actual)
        let rhs = unquote(expected.trimmingCharacters(in: .whitespacesAndNewlines))
        if op == "=~" {
            return regexMatches(lhs, expression: rhs)
        }
        if let leftNumber = Double(lhs), let rightNumber = Double(rhs) {
            switch op {
            case "==", "=": return leftNumber == rightNumber
            case "!=": return leftNumber != rightNumber
            case ">": return leftNumber > rightNumber
            case "<": return leftNumber < rightNumber
            case ">=": return leftNumber >= rightNumber
            case "<=": return leftNumber <= rightNumber
            default: return false
            }
        }
        switch op {
        case "==", "=": return lhs == rhs
        case "!=": return lhs != rhs
        default: return false
        }
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
        if value is NSNull { return false }
        if let number = value as? NSNumber {
            if String(cString: number.objCType) == "c" { return number.boolValue }
            return number.doubleValue != 0
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.lowercased() != "false" && trimmed != "0"
        }
        if let array = value as? [Any] { return !array.isEmpty }
        if let dictionary = value as? [String: Any] { return !dictionary.isEmpty }
        return true
    }

    // MARK: - Transforms

    private func splitTransforms(_ rawRule: String) -> (path: String, transforms: [RegexTransform]) {
        let parts = rawRule.components(separatedBy: "##")
        guard parts.count > 1 else { return (rawRule, []) }
        let path = parts[0]
        let pattern = parts[1]
        let replacement = parts.count > 2 ? parts[2] : ""
        guard !pattern.isEmpty else { return (path, []) }
        return (path, [RegexTransform(pattern: pattern, replacement: replacement, replaceFirst: parts.count > 3)])
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
            guard let regex = try? NSRegularExpression(pattern: transform.pattern) else {
                if transform.replaceFirst {
                    text = transform.replacement
                } else {
                    text = text.replacingOccurrences(of: transform.pattern, with: transform.replacement)
                }
                continue
            }
            let fullRange = NSRange(location: 0, length: (text as NSString).length)
            if transform.replaceFirst {
                let source = text as NSString
                guard let match = regex.firstMatch(in: text, options: [], range: fullRange) else {
                    text = ""
                    continue
                }
                let matched = source.substring(with: match.range)
                let matchedRange = NSRange(location: 0, length: (matched as NSString).length)
                guard let inner = regex.firstMatch(in: matched, options: [], range: matchedRange) else {
                    text = ""
                    continue
                }
                let expanded = regex.replacementString(
                    for: inner,
                    in: matched,
                    offset: 0,
                    template: transform.replacement
                )
                text = (matched as NSString).replacingCharacters(in: inner.range, with: expanded)
            } else {
                text = regex.stringByReplacingMatches(
                    in: text,
                    options: [],
                    range: fullRange,
                    withTemplate: transform.replacement
                )
            }
        }
        return text
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
                val = (value(from: item, path: key, variables: variables)).map { stringify($0) } ?? ""
            } else if let direct = item[key] {
                val = stringify(direct)
            } else if let fromPath = value(from: item, path: key, variables: variables) {
                val = stringify(fromPath)
            } else if let varVal = variables[key] {
                val = stringify(varVal)
            } else if key.contains("java.") || key.contains("+") || key.contains("?") {
                val = evaluateRawJS(script: key, object: item, extraVariables: variables).map { stringify($0) } ?? ""
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

        var trailingRegex: [(pattern: String, replacement: String)] = []
        if script.hasPrefix("##") {
            let parts = script.components(separatedBy: "##").dropFirst()
            var index = parts.startIndex
            while index < parts.endIndex {
                let pattern = parts[index]
                let replacement = parts.index(after: index) < parts.endIndex ? parts[parts.index(after: index)] : ""
                if !pattern.isEmpty { trailingRegex.append((pattern, replacement)) }
                index = parts.index(index, offsetBy: 2, limitedBy: parts.endIndex) ?? parts.endIndex
            }
            var text = stringify(object)
            for t in trailingRegex {
                text = text.replacingOccurrences(of: t.pattern, with: t.replacement, options: .regularExpression)
            }
            return text
        }

        if script.contains("##") {
            if let lineBreak = script.range(of: "\n##", options: .backwards) {
                let hashStart = script.index(after: lineBreak.lowerBound)
                let regexText = String(script[hashStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                script = String(script[..<lineBreak.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = regexText.components(separatedBy: "##").dropFirst()
                var index = parts.startIndex
                while index < parts.endIndex {
                    let pattern = parts[index]
                    let replacement = parts.index(after: index) < parts.endIndex ? parts[parts.index(after: index)] : ""
                    if !pattern.isEmpty { trailingRegex.append((pattern, replacement)) }
                    index = parts.index(index, offsetBy: 2, limitedBy: parts.endIndex) ?? parts.endIndex
                }
            } else if let hashRange = script.range(of: "##") {
                let regexText = String(script[hashRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = regexText.components(separatedBy: "##").dropFirst()
                if parts.count >= 2 {
                    script = String(script[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    var index = parts.startIndex
                    while index < parts.endIndex {
                        let pattern = parts[index]
                        let replacement = parts.index(after: index) < parts.endIndex ? parts[parts.index(after: index)] : ""
                        if !pattern.isEmpty { trailingRegex.append((pattern, replacement)) }
                        index = parts.index(index, offsetBy: 2, limitedBy: parts.endIndex) ?? parts.endIndex
                    }
                }
            }
        }

        let jsResult = evaluateRawJS(script: script, object: object, extraVariables: extraVariables)
        guard !trailingRegex.isEmpty, let jsResult else { return jsResult }
        var text = stringify(jsResult)
        for t in trailingRegex {
            text = text.replacingOccurrences(of: t.pattern, with: t.replacement, options: .regularExpression)
        }
        return text
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
            return ""
        }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text == "<null>" ? "" : text
    }
}