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

    struct RegexTransform {
        let pattern: String
        let replacement: String
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
        if let rule, let selected = value(from: object, path: rule, variables: variables) {
            if let array = selected as? [[String: Any]] {
                return array
            }
            if let array = selected as? [Any] {
                var flattened: [[String: Any]] = []
                func extractDicts(_ item: Any) {
                    if let dict = item as? [String: Any] {
                        flattened.append(dict)
                    } else if let el = item as? SwiftSoup.Element {
                        let text = (try? el.text()) ?? ""
                        let href = (try? el.attr("href")) ?? ""
                        flattened.append(["name": text, "title": text, "url": href, "chapterUrl": href, "href": href, "n": text, "u": href])
                    } else if let bridge = item as? LegadoElementBridge {
                        let text = bridge.text()
                        let href = (try? bridge.element.attr("href")) ?? ""
                        flattened.append(["name": text, "title": text, "url": href, "chapterUrl": href, "href": href, "n": text, "u": href])
                    } else if let subArray = arrayValues(item) {
                        for sub in subArray {
                            extractDicts(sub)
                        }
                    }
                }
                for item in array {
                    extractDicts(item)
                }
                if !flattened.isEmpty {
                    return flattened
                }
            }
            if let dict = selected as? [String: Any] {
                // If dictionary values contain lists of chapter dicts (e.g. volumes -> chapters), extract them
                var nestedDicts: [[String: Any]] = []
                for val in dict.values {
                    if let arr = val as? [[String: Any]] {
                        nestedDicts.append(contentsOf: arr)
                    } else if let arr = val as? [Any] {
                        for el in arr {
                            if let d = el as? [String: Any] { nestedDicts.append(d) }
                        }
                    }
                }
                if !nestedDicts.isEmpty {
                    return nestedDicts
                }
                return [dict]
            }
            // Legado's @js list rules commonly return JSON.stringify(...)
            // rather than a native JS array. JavaScriptCore bridges that
            // result back to Swift as a String, so decode it before falling
            // back to recursive dictionary discovery.
            if let text = selected as? String,
               let data = text.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                return list(from: decoded, rule: "$[*]", variables: variables)
            }
        }
        return collectDictionaries(object)
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
        if let rule, let extracted = value(from: object, path: rule, variables: variables) {
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
                let interpolated = interpolateTemplate(trimmed, item: item, variables: variables).trimmingCharacters(in: .whitespacesAndNewlines)
                // If the interpolated template is already a URL or relative path:
                if interpolated.hasPrefix("http://") || interpolated.hasPrefix("https://") || interpolated.hasPrefix("/") {
                    let cleanedURL = splitTransforms(interpolated).path
                    if !cleanedURL.isEmpty {
                        return cleanedURL
                    }
                }
                if interpolated.hasPrefix("@js:") || interpolated.hasPrefix("<js>") || interpolated.contains("@js:") || interpolated.contains("<js>") || interpolated.contains("$.") || interpolated.contains("@json:") {
                    if let value = value(from: item, path: interpolated, variables: variables) {
                        let text = stringify(value)
                        if !text.isEmpty {
                            return text
                        }
                    }
                } else if !interpolated.isEmpty {
                    return splitTransforms(interpolated).path
                }
            }
            if let value = value(from: item, path: rule, variables: variables) {
                let text = stringify(value)
                if !text.isEmpty {
                    return text
                }
            }
        }
        for key in fallbackKeys {
            if let value = item[key] {
                let text = stringify(value)
                if !text.isEmpty {
                    return text
                }
            }
            // Case-insensitive fallback: e.g. "chaptername" vs "chapterName"
            let lowerKey = key.lowercased()
            if let matchKey = item.keys.first(where: { $0.lowercased() == lowerKey }),
               let value = item[matchKey] {
                let text = stringify(value)
                if !text.isEmpty {
                    return text
                }
            }
        }
        return nil
    }

    func value(from object: Any, path rawPath: String, variables: [String: Any] = [:]) -> Any? {
        var trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return object }

        // 1. Strip leading @json: if present
        if trimmed.hasPrefix("@json:") {
            trimmed = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // 2. Chained <js>...</js>subrule: e.g. <js>...</js>$[*]
        if trimmed.hasPrefix("<js>") {
            if let endRange = trimmed.range(of: "</js>") {
                let jsCode = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: 4)..<endRange.lowerBound])
                let remainingRule = String(trimmed[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let jsResult = evaluateRawJS(script: jsCode, object: object, extraVariables: variables) {
                    if remainingRule.isEmpty {
                        return jsResult
                    }
                    var nextObj: Any = jsResult
                    if let str = jsResult as? String,
                       let data = str.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                        nextObj = parsed
                    }
                    return value(from: nextObj, path: remainingRule, variables: variables)
                }
                return nil
            }
        }

        // 3. Pure @js: rule
        if trimmed.hasPrefix("@js:") {
            return evaluateJS(rule: trimmed, object: object, extraVariables: variables)
        }

        // 4. Subrule followed by @js: e.g. $.title@js:result.trim()
        if let jsRange = trimmed.range(of: "@js:") {
            let left = String(trimmed[..<jsRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(trimmed[jsRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let intermediate: Any?
            if left.isEmpty {
                intermediate = object
            } else if let val = value(from: object, path: left, variables: variables) {
                intermediate = val
            } else if let str = object as? String, !str.hasPrefix("{") && !str.hasPrefix("[") {
                let base = (variables["baseUrl"] as? String).flatMap { URL(string: $0) } ?? URL(string: "http://localhost/")!
                intermediate = try? HtmlRuleExtractor(executionContext: executionContext).select(str, baseUrl: base, listRule: left)
            } else {
                intermediate = nil
            }
            if let intermediate {
                return evaluateRawJS(script: right, object: intermediate, extraVariables: variables)
            }
            return nil
        }
        if let jsStartRange = trimmed.range(of: "<js>"), let jsEndRange = trimmed.range(of: "</js>") {
            let left = String(trimmed[..<jsStartRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let jsCode = String(trimmed[jsStartRange.upperBound..<jsEndRange.lowerBound])
            let intermediate: Any?
            if left.isEmpty {
                intermediate = object
            } else if let val = value(from: object, path: left, variables: variables) {
                intermediate = val
            } else if let str = object as? String, !str.hasPrefix("{") && !str.hasPrefix("[") {
                let base = (variables["baseUrl"] as? String).flatMap { URL(string: $0) } ?? URL(string: "http://localhost/")!
                intermediate = try? HtmlRuleExtractor(executionContext: executionContext).select(str, baseUrl: base, listRule: left)
            } else {
                intermediate = nil
            }
            if let intermediate {
                return evaluateRawJS(script: jsCode, object: intermediate, extraVariables: variables)
            }
            return nil
        }

        // 5. Chained @json: e.g. path@json:subpath
        if let jsonRange = trimmed.range(of: "@json:") {
            let left = String(trimmed[..<jsonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(trimmed[jsonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let intermediate: Any? = left.isEmpty ? object : value(from: object, path: left, variables: variables)
            if let intermediate {
                var nextObj: Any = intermediate
                if let str = intermediate as? String,
                   let data = str.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    nextObj = parsed
                }
                return value(from: nextObj, path: right, variables: variables)
            }
            return nil
        }

        // 6. Check for java.* standalone script
        if LegadoRuleResolver().isJavaScriptRule(trimmed) && !trimmed.contains("##") {
            return evaluateJS(rule: trimmed, object: object, extraVariables: variables)
        }

        // 7. Regex transforms with ##
        let split = splitTransforms(trimmed)
        let directiveResult = applyDirectives(from: object, path: split.path)
        let operatorPath: String
        switch directiveResult {
        case .path(let path):
            operatorPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        case .value(let value):
            return applyTransforms(split.transforms, to: value)
        }
        guard !operatorPath.isEmpty else {
            return applyTransforms(split.transforms, to: object)
        }
        if let fallbackParts = RuleOperatorSplitter.split(operatorPath, separator: "||") {
            for part in fallbackParts {
                if let value = value(from: object, path: appendTransforms(split.transforms, to: part), variables: variables) {
                    return value
                }
            }
            return nil
        }
        if let mergeParts = RuleOperatorSplitter.split(operatorPath, separator: "%%") {
            let values = mergeParts.compactMap { valueForSinglePath(from: object, path: normalize($0)) }
            let flattened = values.flatMap { value -> [Any] in
                if let array = value as? [Any] { return array }
                return [value]
            }
            return flattened.isEmpty ? nil : applyTransforms(split.transforms, to: flattened)
        }
        let path = normalize(operatorPath)
        guard !path.isEmpty else {
            return applyTransforms(split.transforms, to: object)
        }
        if let value = valueForSinglePath(from: object, path: path) {
            return applyTransforms(split.transforms, to: value)
        }
        return nil
    }

    private func applyDirectives(from object: Any, path: String) -> DirectiveResult {
        var output = path
        for directive in extractPutDirectives(from: output) {
            if let value = value(from: object, path: directive.valueRule) {
                directiveStore.put(directive.key, value: value)
                executionContext.put(stringify(value), for: directive.key)
            }
        }
        output = removePutDirectives(from: output)
        let directOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = directGetKey(from: directOutput), let value = directiveStore.get(key) {
            return .value(value)
        }
        output = replaceGetDirectives(in: output)

        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return .path(trimmed)
    }

    private func extractPutDirectives(from rule: String) -> [(key: String, valueRule: String)] {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)@put:\{([^}]*)\}"#) else { return [] }
        let range = NSRange(rule.startIndex..<rule.endIndex, in: rule)
        return regex.matches(in: rule, range: range).flatMap { match -> [(key: String, valueRule: String)] in
            guard let bodyRange = Range(match.range(at: 1), in: rule) else { return [] }
            return splitTopLevel(String(rule[bodyRange]), separator: ",")
                .compactMap { entry in
                    let parts = splitTopLevel(entry, separator: ":", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    let key = unquote(parts[0].trimmingCharacters(in: .whitespacesAndNewlines))
                    let valueRule = unquote(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
                    return key.isEmpty || valueRule.isEmpty ? nil : (key, valueRule)
                }
        }
    }

    private func removePutDirectives(from rule: String) -> String {
        rule.replacingOccurrences(of: #"(?i)@put:\{[^}]*\}"#, with: "", options: .regularExpression)
    }

    private func replaceGetDirectives(in rule: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)@get:\{([^}]*)\}"#) else { return rule }
        var output = rule
        let matches = regex.matches(in: rule, range: NSRange(rule.startIndex..<rule.endIndex, in: rule)).reversed()
        for match in matches {
            guard let fullRange = Range(match.range(at: 0), in: output),
                  let keyRange = Range(match.range(at: 1), in: output) else { continue }
            let key = String(output[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            output.replaceSubrange(fullRange, with: stringify(directiveStore.get(key) ?? ""))
        }
        return output
    }

    private func directGetKey(from rule: String) -> String? {
        let lower = rule.lowercased()
        guard lower.hasPrefix("@get:") else { return nil }
        if lower.hasPrefix("@get:{"), rule.hasSuffix("}") {
            return String(rule.dropFirst(6).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(rule.dropFirst(5))
            .components(separatedBy: CharacterSet(charactersIn: "@#"))
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func interpolateTemplate(_ template: String, item: [String: Any], variables: [String: Any]) -> String {
        var output = template
        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([^{}]+)\s*\}\}"#) else { return template }
        let nsText = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let keyRange = match.range(at: 1)
            let fullRange = match.range(at: 0)
            let key = nsText.substring(with: keyRange).trimmingCharacters(in: .whitespacesAndNewlines)
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
            if let targetRange = Range(fullRange, in: output) {
                output.replaceSubrange(targetRange, with: val)
            }
        }
        return output
    }

    private func appendTransforms(_ transforms: [RegexTransform], to path: String) -> String {
        guard !transforms.isEmpty else { return path }
        var res = path
        for t in transforms {
            res += "##\(t.pattern)##\(t.replacement)"
        }
        return res
    }

    private func valueForSinglePath(from object: Any, path: String) -> Any? {
        walk(object, parts: tokenize(path), index: 0)
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
            let ch = path[index]
            if ch == "[" {
                flush()
                var depth = 1
                var quote: Character?
                var escaped = false
                var cursor = path.index(after: index)
                var token = ""
                while cursor < path.endIndex, depth > 0 {
                    let c = path[cursor]
                    if let q = quote {
                        token.append(c)
                        if escaped { escaped = false }
                        else if c == "\\" { escaped = true }
                        else if c == q { quote = nil }
                    } else if c == "\"" || c == "'" {
                        quote = c; token.append(c)
                    } else if c == "[" {
                        depth += 1; token.append(c)
                    } else if c == "]" {
                        depth -= 1
                        if depth > 0 { token.append(c) }
                    } else {
                        token.append(c)
                    }
                    cursor = path.index(after: cursor)
                }
                let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    let unquoted = unquote(trimmed)
                    parts.append(unquoted)
                }
                index = cursor
                continue
            }
            if ch == "." || ch == "/" {
                flush()
                if ch == "." {
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
            buffer.append(ch)
            index = path.index(after: index)
        }
        flush()
        return parts
    }

    private func walk(_ current: Any, parts: [String], index: Int) -> Any? {
        guard index < parts.count else { return current }
        let part = parts[index]

        // Auto-deserialize stringified JSON if current is a JSON String
        var node = current
        if let str = node as? String, (str.hasPrefix("{") || str.hasPrefix("[")),
           let data = str.data(using: .utf8),
           let unpacked = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            node = unpacked
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

        if let filter = filterPredicate(part), let array = arrayValues(node) {
            let filtered = array.filter { matchesPredicate($0, filter: filter) }
            return walk(filtered, parts: parts, index: index + 1)
        }

        // Array slicing: e.g. 0:20 or :10 or -5:
        if let array = arrayValues(node), part.contains(":") {
            let sliceParts = part.components(separatedBy: ":")
            if sliceParts.count == 2 {
                let count = array.count
                let startRaw = sliceParts[0].trimmingCharacters(in: .whitespaces)
                let endRaw = sliceParts[1].trimmingCharacters(in: .whitespaces)
                let startIdx = startRaw.isEmpty ? 0 : (Int(startRaw) ?? 0)
                let endIdx = endRaw.isEmpty ? count : (Int(endRaw) ?? count)
                let resolvedStart = max(0, min(count, startIdx < 0 ? count + startIdx : startIdx))
                let resolvedEnd = max(0, min(count, endIdx < 0 ? count + endIdx : endIdx))
                if resolvedStart <= resolvedEnd {
                    let sliced = Array(array[resolvedStart..<resolvedEnd])
                    return walk(sliced, parts: parts, index: index + 1)
                }
            }
        }

        if let dict = node as? [String: Any] {
            if part == "*" {
                let values = Array(dict.values)
                var flattened: [Any] = []
                for val in values {
                    if let subArray = arrayValues(val) {
                        flattened.append(contentsOf: subArray)
                    } else {
                        flattened.append(val)
                    }
                }
                return walk(flattened, parts: parts, index: index + 1)
            }
            guard let value = lookup(dict, key: part) else { return nil }
            return walk(value, parts: parts, index: index + 1)
        }

        if let array = arrayValues(node) {
            if part == "*" {
                let mapped = array.compactMap { element -> Any? in
                    walk(element, parts: parts, index: index + 1)
                }
                if mapped.isEmpty { return nil }
                var flattened: [Any] = []
                mapped.forEach { appendFlattened($0, to: &flattened) }
                return flattened
            }
            if let number = Int(part) {
                let resolved = number < 0 ? array.count + number : number
                guard array.indices.contains(resolved) else { return nil }
                return walk(array[resolved], parts: parts, index: index + 1)
            }
            let mapped = array.compactMap { element -> Any? in
                guard let result = walk(element, parts: parts, index: index) else { return nil }
                return result
            }
            if mapped.isEmpty { return nil }
            var flattened: [Any] = []
            mapped.forEach { appendFlattened($0, to: &flattened) }
            return flattened
        }
        return nil
    }

    private func lookup(_ dict: [String: Any], key: String) -> Any? {
        dict[key] ?? dict[key.lowercased()] ?? dict[key.uppercased()]
    }

    private func children(of value: Any) -> [Any] {
        if let dict = value as? [String: Any] { return Array(dict.values) }
        if let array = arrayValues(value) { return array }
        return []
    }

    private func arrayValues(_ value: Any) -> [Any]? {
        if let array = value as? [Any] { return array }
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries.map { $0 as Any }
        }
        if let nsArray = value as? NSArray {
            return nsArray.map { $0 }
        }
        return nil
    }

    private func appendFlattened(_ value: Any, to output: inout [Any]) {
        if let array = value as? [Any] { array.forEach { appendFlattened($0, to: &output) } }
        else { output.append(value) }
    }

    private func filterPredicate(_ part: String) -> (path: String, op: String?, expected: String?)? {
        guard part.hasPrefix("?(") && part.hasSuffix(")") else { return nil }
        let expression = String(part.dropFirst(2).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        for op in ["!=", "==", ">=", "<=", "=", ">", "<"] {
            if let range = expression.range(of: op) {
                return (String(expression[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines), op, String(expression[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return (expression, nil, nil)
    }

    private func matchesPredicate(_ value: Any, filter: (path: String, op: String?, expected: String?)) -> Bool {
        let key = filter.path.replacingOccurrences(of: "@.", with: "")
        let actual: Any?
        if key.isEmpty || key == "@" { actual = value }
        else { actual = valueForSinglePath(from: value, path: key) }
        guard let actual else { return false }
        guard let op = filter.op, let expected = filter.expected else { return truthy(actual) }
        let lhs = stringify(actual)
        let rhs = unquote(expected)
        if let l = Double(lhs), let r = Double(rhs) {
            switch op { case "==", "=": return l == r; case "!=": return l != r; case ">": return l > r; case "<": return l < r; case ">=": return l >= r; case "<=": return l <= r; default: return false }
        }
        switch op { case "==", "=": return lhs == rhs; case "!=": return lhs != rhs; default: return false }
    }

    private func truthy(_ value: Any) -> Bool {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.doubleValue != 0 }
        if let text = value as? String { return !text.isEmpty && text.lowercased() != "false" }
        return true
    }

    private func normalize(_ rule: String) -> String {
        var output = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasPrefix("@json:") {
            output = String(output.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if output.hasPrefix("$..") {
            output.removeFirst() // `$..name` -> `..name`, tokenizer emits `**`.
            return output
        }
        if output.hasPrefix("$.") {
            output.removeFirst(2)
        } else if output.hasPrefix("$") {
            output.removeFirst()
        }
        output = output
            .replacingOccurrences(of: #"(?i)@put:\{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)@get:\{([^}]*)\}"#, with: "$1", options: .regularExpression)
        if output.hasPrefix("@json:") {
            output = String(output.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if output.hasPrefix("$..") {
            output.removeFirst()
        } else if output.hasPrefix("$.") {
            output.removeFirst(2)
        }
        if output.hasPrefix("$") {
            output.removeFirst()
        }
        if output.hasPrefix("@") && !output.hasPrefix("@.") {
            output.removeFirst()
        }
        if output.contains("&&") {
            output = output
                .components(separatedBy: "&&")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && !$0.hasPrefix("@") }
                .joined(separator: ".")
        }
        if !output.contains("[?"),
           let atIndex = output.lastIndex(of: "@"), atIndex != output.startIndex {
            output.replaceSubrange(atIndex...atIndex, with: ".")
        }
        return output.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    private func splitTransforms(_ rawRule: String) -> (path: String, transforms: [RegexTransform]) {
        let parts = rawRule.components(separatedBy: "##")
        guard parts.count > 1 else {
            return (rawRule, [])
        }
        if parts.first == "" {
            var transforms: [RegexTransform] = []
            var i = 1
            while i < parts.count {
                let pattern = parts[i]
                let replacement = (i + 1 < parts.count) ? parts[i + 1] : ""
                if !pattern.isEmpty {
                    transforms.append(RegexTransform(pattern: pattern, replacement: replacement))
                }
                i += 2
            }
            return ("", transforms)
        }
        let path = parts[0]
        var transforms: [RegexTransform] = []
        var i = 1
        while i < parts.count {
            let pattern = parts[i]
            let replacement = (i + 1 < parts.count) ? parts[i + 1] : ""
            if !pattern.isEmpty {
                transforms.append(RegexTransform(pattern: pattern, replacement: replacement))
            }
            i += 2
        }
        return (path, transforms)
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

    private func splitTopLevel(_ value: String, separator: Character, maxSplits: Int = Int.max) -> [String] {
        var output: [String] = []
        var current = ""
        var quote: Character?
        var braceDepth = 0
        var bracketDepth = 0
        var parenDepth = 0
        var splits = 0
        var previous: Character?

        for character in value {
            if let activeQuote = quote {
                current.append(character)
                if character == activeQuote, previous != "\\" {
                    quote = nil
                }
                previous = character
                continue
            }

            switch character {
            case "\"", "'":
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
                    output.append(current)
                    current = ""
                    splits += 1
                } else {
                    current.append(character)
                }
            }
            previous = character
        }
        output.append(current)
        return output
    }

    private func applyTransforms(_ transforms: [RegexTransform], to value: Any) -> Any {
        guard !transforms.isEmpty else { return value }
        if let array = value as? [Any] {
            return array.map { applyTransforms(transforms, to: $0) }
        }
        var text = stringify(value)
        for t in transforms {
            text = text.replacingOccurrences(
                of: t.pattern,
                with: t.replacement,
                options: .regularExpression
            )
        }
        return text
    }

    private func collectDictionaries(_ object: Any) -> [[String: Any]] {
        if let dict = object as? [String: Any] {
            var result = [dict]
            for value in dict.values {
                result.append(contentsOf: collectDictionaries(value))
            }
            return result
        }
        if let array = object as? [Any] {
            return array.flatMap { collectDictionaries($0) }
        }
        return []
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

        var variables: [String: Any] = [
            "result": object
        ]

        // Apply extraVariables first so root document and caller context take precedence
        for (k, v) in extraVariables {
            variables[k] = v
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
}
