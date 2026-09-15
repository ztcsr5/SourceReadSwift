import Foundation
import SwiftSoup

final class RuleDirectiveStore {
    private var values: [String: String] = [:]

    func put(_ key: String, value: String) {
        let clean = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        values[clean] = value
    }

    func get(_ key: String) -> String {
        values[key.trimmingCharacters(in: .whitespacesAndNewlines)] ?? ""
    }
}

struct HtmlRuleExtractor {
    private let directiveStore: RuleDirectiveStore
    private let executionContext: RuleExecutionContext

    init(
        directiveStore: RuleDirectiveStore = RuleDirectiveStore(),
        executionContext: RuleExecutionContext = RuleExecutionContext()
    ) {
        self.directiveStore = directiveStore
        self.executionContext = executionContext
    }

    func select(_ html: String, baseUrl: URL, listRule: String) throws -> [Element] {
        let document = try SwiftSoup.parse(html, baseUrl.absoluteString)
        return try select(from: document, rule: listRule, baseUrl: baseUrl)
    }

    func value(
        from root: Element,
        rule: String?,
        fallback: String? = nil,
        baseUrl: URL? = nil,
        variables: [String: Any] = [:]
    ) throws -> String {
        let selectedRule = rule ?? fallback
        guard let selectedRule, !selectedRule.isEmpty else { return "" }

        var trimmed = selectedRule.trimmingCharacters(in: .whitespacesAndNewlines)

        // Stage 1: Template Interpolation {{...}}
        if trimmed.contains("{{") && trimmed.contains("}}") {
            let interpolated = try interpolateTemplate(trimmed, root: root, baseUrl: baseUrl, variables: variables)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if LegadoRuleResolver().isJavaScriptRule(interpolated) {
                return try evaluateJSWithTrailingRegex(rule: interpolated, rootHtml: try root.outerHtml(), baseUrl: baseUrl, extraVariables: variables)
            }
            if !interpolated.isEmpty {
                return interpolated
            }
            return ""
        }

        if LegadoRuleResolver().isJavaScriptRule(trimmed) {
            return try evaluateJSWithTrailingRegex(rule: trimmed, rootHtml: try root.outerHtml(), baseUrl: baseUrl, extraVariables: variables)
        }

        // Support chained JavaScript rules: Selector@js:script or Selector<js>script</js>
        if let jsRange = trimmed.range(of: "@js:"), jsRange.lowerBound > trimmed.startIndex {
            let prefix = String(trimmed[..<jsRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let script = String(trimmed[jsRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let extracted = try self.value(from: root, rule: prefix, fallback: nil, baseUrl: baseUrl, variables: variables)
            var chainedVariables = variables
            chainedVariables["result"] = extracted
            chainedVariables["src"] = extracted
            chainedVariables["html"] = extracted
            return try evaluateJSWithTrailingRegex(rule: script, rootHtml: extracted, baseUrl: baseUrl, extraVariables: chainedVariables)
        }

        if let jsStart = trimmed.range(of: "<js>"), jsStart.lowerBound > trimmed.startIndex {
            let prefix = String(trimmed[..<jsStart.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let script = String(trimmed[jsStart.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let extracted = try self.value(from: root, rule: prefix, fallback: nil, baseUrl: baseUrl, variables: variables)
            var chainedVariables = variables
            chainedVariables["result"] = extracted
            chainedVariables["src"] = extracted
            chainedVariables["html"] = extracted
            return try evaluateJSWithTrailingRegex(rule: script, rootHtml: extracted, baseUrl: baseUrl, extraVariables: chainedVariables)
        }

        if let alternatives = RuleOperatorSplitter.split(trimmed, separator: "||") {
            for alternative in alternatives {
                let trimmedAlt = alternative.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedAlt.hasPrefix("$.") || trimmedAlt.hasPrefix("@json:") {
                    continue
                }
                do {
                    let value = try self.value(from: root, rule: trimmedAlt, fallback: nil, baseUrl: baseUrl, variables: variables)
                    if !value.isEmpty { return value }
                } catch {
                    continue
                }
            }
            return ""
        }

        if let mergeParts = RuleOperatorSplitter.split(trimmed, separator: "%%") {
            let lists = try mergeParts
                .map { try valuesForSingleRule(from: root, rule: $0, baseUrl: baseUrl) }
                .filter { !$0.isEmpty }
            return interleave(lists).joined(separator: "\n")
        }

        let values = try valuesForSingleRule(from: root, rule: trimmed, baseUrl: baseUrl)
        return values.joined(separator: "\n")
    }

    private func valuesForSingleRule(from root: Element, rule: String, baseUrl: URL?) throws -> [String] {
        let materializedRule = try applyDirectives(root: root, rule: rule, baseUrl: baseUrl)
        if materializedRule.isEmpty {
            return []
        }
        if isDirectGetRule(rule) {
            return [materializedRule]
        }

        if let jsonRange = materializedRule.range(of: "@json:") {
            let left = String(materializedRule[..<jsonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(materializedRule[jsonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawText: String
            if !left.isEmpty {
                rawText = (try? valuesForSingleRule(from: root, rule: left, baseUrl: baseUrl))?.joined(separator: "\n") ?? ""
            } else {
                rawText = (try? root.outerHtml()) ?? ""
            }
            if let obj = ResponseFormatDetector.jsonObject(from: rawText) {
                if let val = JSONRuleExtractor().value(from: obj, path: right) {
                    if let arr = val as? [Any] {
                        return arr.map { JSONRuleExtractor().stringify($0) }.filter { !$0.isEmpty }
                    }
                    let str = JSONRuleExtractor().stringify(val)
                    return str.isEmpty ? [] : [str]
                }
            }
            return []
        }

        // Try XPath translator first
        if let xpathSplit = XPathRuleTranslator.valueRule(materializedRule) {
            let targets = try select(from: root, rule: xpathSplit.selector, baseUrl: baseUrl)
            let attrParts = xpathSplit.attribute.components(separatedBy: "##")
            let attr = attrParts.first ?? "text"
            if attr == "all" {
                let joined = try targets.map { try $0.text() }.joined(separator: "\n")
                let transformed = applyRegexTransforms(attrParts.dropFirst(), to: joined)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return transformed.isEmpty ? [] : [transformed]
            }
            return try targets.compactMap { target in
                let value = try attributeValue(from: target, attr: attr)
                let trimmed = applyRegexTransforms(attrParts.dropFirst(), to: value)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if ["href", "src", "url"].contains(attr.lowercased()), let baseUrl {
                    let absolute = absolutize(trimmed, base: baseUrl)
                    return absolute.isEmpty ? nil : absolute
                }
                return trimmed.isEmpty ? nil : trimmed
            }
        }

        // Try Legado default syntax translator (class., id., tag., @ chaining)
        if let translated = LegadoDefaultRuleTranslator.translateValueRule(materializedRule) {
            let currentElements = LegadoDefaultRuleTranslator.executeSteps(translated.steps, on: root)

            if translated.attribute == "all" {
                let joined = try currentElements.map { try $0.text() }.joined(separator: "\n")
                let transformed = applyRegexTransforms(translated.regexTransforms[...], to: joined)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return transformed.isEmpty ? [] : [transformed]
            }

            return try currentElements.compactMap { target in
                let value = try attributeValue(from: target, attr: translated.attribute)
                let trimmed = applyRegexTransforms(translated.regexTransforms[...], to: value)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if ["href", "src", "url"].contains(translated.attribute.lowercased()), let baseUrl {
                    let absolute = absolutize(trimmed, base: baseUrl)
                    return absolute.isEmpty ? nil : absolute
                }
                return trimmed.isEmpty ? nil : trimmed
            }
        }

        let split = splitSelectorAndAttribute(materializedRule)
        let targets = try select(from: root, rule: split.selector, baseUrl: baseUrl)
        let attrParts = split.attribute.components(separatedBy: "##")
        let attr = attrParts.first ?? "text"
        if attr == "all" {
            let joined = try targets.map { try $0.text() }.joined(separator: "\n")
            let transformed = applyRegexTransforms(attrParts.dropFirst(), to: joined)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return transformed.isEmpty ? [] : [transformed]
        }
        return try targets.compactMap { target in
            let value = try attributeValue(from: target, attr: attr)
            let trimmed = applyRegexTransforms(attrParts.dropFirst(), to: value)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if ["href", "src", "url"].contains(attr.lowercased()), let baseUrl {
                let absolute = absolutize(trimmed, base: baseUrl)
                return absolute.isEmpty ? nil : absolute
            }
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func attributeValue(from target: Element, attr: String) throws -> String {
        let normalizedAttr = attr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedAttr == "text" || normalizedAttr == "text()" {
            if target.children().contains(where: { ["p", "br", "div", "li"].contains($0.tagName().lowercased()) }) {
                if let html = try? target.html() {
                    let withBreaks = html
                        .replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
                        .replacingOccurrences(of: "(?i)</p\\s*>", with: "\n", options: .regularExpression)
                        .replacingOccurrences(of: "(?i)</div\\s*>", with: "\n", options: .regularExpression)
                    if let parsedDoc = try? SwiftSoup.parse(withBreaks) {
                        return try parsedDoc.text()
                    }
                }
            }
            return try target.text()
        } else if normalizedAttr == "owntext" || normalizedAttr == "owntext()" {
            return try target.ownText()
        } else if normalizedAttr == "textnodes" {
            let nodes = target.textNodes()
            if !nodes.isEmpty {
                return nodes.map { $0.text().trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
            }
            return try target.text()
        } else if normalizedAttr == "html" || normalizedAttr == "html()" {
            return try target.html()
        } else if normalizedAttr.hasPrefix("attr(") && normalizedAttr.hasSuffix(")") {
            let inner = String(attr.dropFirst(5).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            return try target.attr(inner)
        } else {
            return try target.attr(attr)
        }
    }

    func select(from root: Element, rule: String, baseUrl: URL? = nil) throws -> [Element] {
        let materializedRule = try applyDirectives(root: root, rule: rule, baseUrl: baseUrl)
        if materializedRule.isEmpty {
            return [root]
        }
        if let fallbackParts = RuleOperatorSplitter.split(materializedRule, separator: "||") {
            for part in fallbackParts {
                let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedPart.hasPrefix("$.") || trimmedPart.hasPrefix("@json:") || LegadoRuleResolver().isJavaScriptRule(trimmedPart) {
                    continue
                }
                do {
                    let elements = try select(from: root, rule: trimmedPart, baseUrl: baseUrl)
                    if !elements.isEmpty { return elements }
                } catch {
                    continue
                }
            }
            return []
        }
        if let mergeParts = RuleOperatorSplitter.split(materializedRule, separator: "%%") {
            let lists = try mergeParts
                .map { try select(from: root, rule: $0, baseUrl: baseUrl) }
                .filter { !$0.isEmpty }
            return interleave(lists)
        }

        if let xpathSelector = XPathRuleTranslator.selectorRule(materializedRule) {
            let indexed = parseIndexedSelector(xpathSelector)
            let elements: [Element]
            do {
                elements = try root.select(indexed.selector).array()
            } catch {
                return []
            }
            guard let index = indexed.index else { return elements }
            let normalized = index >= 0 ? index : elements.count + index
            guard elements.indices.contains(normalized) else { return [] }
            return [elements[normalized]]
        }

        let steps = LegadoDefaultRuleTranslator.translateSelectorSteps(materializedRule)
        if !steps.isEmpty {
            return LegadoDefaultRuleTranslator.executeSteps(steps, on: root)
        }

        let selector = cleanCSS(materializedRule)
        guard !selector.isEmpty else { return [root] }
        let indexed = parseIndexedSelector(selector)
        let elements: [Element]
        do {
            elements = try root.select(indexed.selector).array()
        } catch {
            return []
        }
        guard let index = indexed.index else { return elements }
        let normalized = index >= 0 ? index : elements.count + index
        guard elements.indices.contains(normalized) else { return [] }
        return [elements[normalized]]
    }

    private func splitSelectorAndAttribute(_ rule: String) -> (selector: String, attribute: String) {
        let parts = rule.components(separatedBy: "@")
        guard parts.count > 1 else {
            return (rule, "text")
        }
        let selector = parts.dropLast().joined(separator: "@")
        let attribute = parts.last?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "text"
        return (selector, attribute)
    }

    private func parseIndexedSelector(_ selector: String) -> (selector: String, index: Int?) {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^(.*?)(?:@(-?\d+)|:eq\((-?\d+)\))$"#) else {
            return (trimmed, nil)
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else {
            return (trimmed, nil)
        }
        let selectorRange = match.range(at: 1)
        let firstIndexRange = match.range(at: 2)
        let secondIndexRange = match.range(at: 3)
        guard let cssRange = Range(selectorRange, in: trimmed) else {
            return (trimmed, nil)
        }
        let rawIndex: String?
        if let range = Range(firstIndexRange, in: trimmed) {
            rawIndex = String(trimmed[range])
        } else if let range = Range(secondIndexRange, in: trimmed) {
            rawIndex = String(trimmed[range])
        } else {
            rawIndex = nil
        }
        return (String(trimmed[cssRange]).trimmingCharacters(in: .whitespacesAndNewlines), rawIndex.flatMap(Int.init))
    }

    private func applyRegexTransforms(_ rawParts: ArraySlice<String>, to value: String) -> String {
        let parts = Array(rawParts)
        guard !parts.isEmpty else { return value }
        var output = value
        var index = 0
        while index < parts.count {
            let pattern = parts[index]
            let replacement = index + 1 < parts.count ? parts[index + 1] : ""
            if !pattern.isEmpty {
                output = output.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
            }
            index += 2
        }
        return output
    }

    private func applyDirectives(root: Element, rule: String, baseUrl: URL?) throws -> String {
        var output = rule
        let putDirectives = extractPutDirectives(from: output)
        for directive in putDirectives {
            let value = try value(from: root, rule: directive.valueRule, fallback: nil, baseUrl: baseUrl)
            directiveStore.put(directive.key, value: value)
            executionContext.put(value, for: directive.key)
        }
        output = removePutDirectives(from: output)
        output = replaceGetDirectives(in: output)
        if output.lowercased().hasPrefix("@get:") {
            let key = String(output.dropFirst(5))
                .components(separatedBy: CharacterSet(charactersIn: "@#"))
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return directiveStore.get(key)
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isDirectGetRule(_ rule: String) -> Bool {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("@get:") else { return false }
        return !trimmed.contains("@text")
            && !trimmed.contains("@href")
            && !trimmed.contains("@src")
            && !trimmed.contains("@html")
            && !trimmed.contains("@ownText")
            && !trimmed.contains("##")
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
            output.replaceSubrange(fullRange, with: directiveStore.get(key))
        }
        return output
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

    func firstRule(_ rule: SourceRule?, keys: [String]) -> String? {
        guard let rule else { return nil }
        for key in keys {
            if let value = rule.fields[key], !value.isEmpty {
                return value
            }
        }
        return rule.raw
    }

    func cleanCSS(_ rule: String) -> String {
        var output = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = output.lowercased()
        if lower.hasPrefix("@css:") {
            output = String(output.dropFirst(5))
        } else if lower.hasPrefix("css:") {
            output = String(output.dropFirst(4))
        }
        return output
            .replacingOccurrences(of: "&&", with: " ")
            .replacingOccurrences(of: #"(?i)@put:\{[^}]*\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)@get:\{[^}]*\}"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func absolutize(_ text: String, base: URL) -> String {
        var clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while clean.hasSuffix("|") || clean.hasSuffix("#") {
            clean = String(clean.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if clean.lowercased().hasPrefix("javascript:") || clean == "#" || clean.isEmpty {
            return ""
        }
        if clean.hasPrefix("@js:") || clean.hasPrefix("<js>") {
            return clean
        }
        var optionsSuffix = ""
        if let commaRange = clean.range(of: ",{") ?? clean.range(of: ", {") {
            optionsSuffix = String(clean[commaRange.lowerBound...])
            clean = String(clean[..<commaRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let absolutized: String
        if let url = URL(string: clean), url.scheme != nil {
            absolutized = url.absoluteString
        } else if let encoded = clean.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(.urlPathAllowed)),
                  let url = URL(string: encoded, relativeTo: base) {
            absolutized = url.absoluteURL.absoluteString
        } else {
            absolutized = URL(string: clean, relativeTo: base)?.absoluteURL.absoluteString ?? clean
        }
        return absolutized + optionsSuffix
    }

    private func interleave<T>(_ lists: [[T]]) -> [T] {
        let maxCount = lists.map(\.count).max() ?? 0
        var output: [T] = []
        for index in 0..<maxCount {
            for list in lists where list.indices.contains(index) {
                output.append(list[index])
            }
        }
        return output
    }

    private func interpolateTemplate(
        _ template: String,
        root: Element,
        baseUrl: URL?,
        variables: [String: Any]
    ) throws -> String {
        var output = template
        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([^{}]+)\s*\}\}"#) else { return template }
        let nsText = template as NSString
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let keyRange = match.range(at: 1)
            let fullRange = match.range(at: 0)
            let expr = nsText.substring(with: keyRange).trimmingCharacters(in: .whitespacesAndNewlines)
            var val = ""
            if expr.hasPrefix("@@") {
                let subRule = String(expr.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                val = (try? self.value(from: root, rule: subRule, fallback: nil, baseUrl: baseUrl, variables: variables)) ?? ""
            } else if expr.hasPrefix("@css:") || expr.hasPrefix("@xpath:") || expr.hasPrefix("class.") || expr.hasPrefix("tag.") || expr.hasPrefix("id.") || expr.hasPrefix(".") || expr.hasPrefix("#") {
                val = (try? self.value(from: root, rule: expr, fallback: nil, baseUrl: baseUrl, variables: variables)) ?? ""
            } else if expr.hasPrefix("$.") || expr.hasPrefix("@json:") {
                let jsonPath = expr.hasPrefix("@json:") ? String(expr.dropFirst(6)) : expr
                if let data = try? root.outerHtml().data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                   let extracted = JSONRuleExtractor().value(from: obj, path: jsonPath) {
                    val = JSONRuleExtractor().stringify(extracted)
                }
            } else if expr == "key" || expr == "keyword" {
                val = (variables["key"] as? String) ?? (variables["keyword"] as? String) ?? ""
            } else if expr == "page" {
                val = "\(variables["page"] ?? 1)"
            } else if let varVal = variables[expr] {
                val = String(describing: varVal)
            } else {
                val = (try? self.value(from: root, rule: expr, fallback: nil, baseUrl: baseUrl, variables: variables)) ?? ""
            }
            if let targetRange = Range(fullRange, in: output) {
                output.replaceSubrange(targetRange, with: val)
            }
        }
        return output
    }

    private func evaluateJSWithTrailingRegex(
        rule: String,
        rootHtml: String,
        baseUrl: URL?,
        extraVariables: [String: Any]
    ) throws -> String {
        var script = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        var chainedSubrule: String? = nil
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if script.hasPrefix("<js>"), let endRange = script.range(of: "</js>") {
            let start = script.index(script.startIndex, offsetBy: 4)
            let jsCode = String(script[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remaining = String(script[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            script = jsCode
            if !remaining.isEmpty {
                chainedSubrule = remaining
            }
        }

        var trailingRegexParts: [String] = []
        if script.hasPrefix("##") {
            trailingRegexParts = Array(script.components(separatedBy: "##").dropFirst())
            return applyRegexTransforms(trailingRegexParts[...], to: rootHtml)
        }

        if script.contains("##") {
            if let lineBreakRange = script.range(of: "\n##", options: .backwards) {
                let hashStart = script.index(after: lineBreakRange.lowerBound)
                let regexText = String(script[hashStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
                script = String(script[..<lineBreakRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                trailingRegexParts = Array(regexText.components(separatedBy: "##").dropFirst())
            } else if let hashRange = script.range(of: "##") {
                let regexText = String(script[hashRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let parts = regexText.components(separatedBy: "##").dropFirst()
                if parts.count >= 2 {
                    script = String(script[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    trailingRegexParts = Array(parts)
                }
            }
        }

        let jsResult: String
        if script.isEmpty {
            jsResult = rootHtml
        } else {
            jsResult = try evaluateJS(rule: script, rootHtml: rootHtml, baseUrl: baseUrl, extraVariables: extraVariables)
        }

        var currentResult = jsResult
        if !trailingRegexParts.isEmpty {
            currentResult = applyRegexTransforms(trailingRegexParts[...], to: currentResult)
        }

        if let chained = chainedSubrule, !chained.isEmpty {
            if chained.hasPrefix("##") {
                let parts = Array(chained.components(separatedBy: "##").dropFirst())
                return applyRegexTransforms(parts[...], to: currentResult)
            } else if chained.hasPrefix("$.") || chained.hasPrefix("@json:") {
                var jsonTarget: Any = currentResult
                if let data = currentResult.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                    jsonTarget = parsed
                }
                let jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
                if let val = jsonExtractor.value(from: jsonTarget, path: chained, variables: extraVariables) {
                    return jsonExtractor.stringify(val)
                }
            } else if chained.hasPrefix("<js>") || chained.hasPrefix("@js:") {
                var chainedVariables = extraVariables
                chainedVariables["result"] = currentResult
                chainedVariables["src"] = currentResult
                chainedVariables["html"] = currentResult
                return try evaluateJSWithTrailingRegex(rule: chained, rootHtml: currentResult, baseUrl: baseUrl, extraVariables: chainedVariables)
            } else if let doc = try? SwiftSoup.parse(currentResult, baseUrl?.absoluteString ?? "") {
                var chainedVariables = extraVariables
                chainedVariables["result"] = currentResult
                chainedVariables["src"] = currentResult
                chainedVariables["html"] = currentResult
                let subVal = try self.value(from: doc, rule: chained, fallback: nil, baseUrl: baseUrl, variables: chainedVariables)
                if !subVal.isEmpty {
                    return subVal
                }
            }
        }

        return currentResult
    }

    private func evaluateJS(
        rule: String,
        rootHtml: String,
        baseUrl: URL?,
        extraVariables: [String: Any]
    ) throws -> String {
        var script = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4))
        } else if script.hasPrefix("<js>") && script.hasSuffix("</js>") {
            let start = script.index(script.startIndex, offsetBy: 4)
            let end = script.index(script.endIndex, offsetBy: -5)
            script = String(script[start..<end])
        }

        let source = extraVariables["source"] as? BookSource
        let runtime = executionContext.jsRuntime(ajaxHandler: { urlText in
            if let source {
                return SynchronousSourceLoader().load(urlText: urlText, source: source)
            }
            return ""
        })

        var variables: [String: Any] = [
            "result": rootHtml,
            "html": rootHtml,
            "src": rootHtml,
            "baseUrl": baseUrl?.absoluteString ?? ""
        ]
        for (k, v) in extraVariables {
            variables[k] = v
        }

        let evaluated = runtime.evaluate(script, variables: variables)
        if case .failure(.javascript) = evaluated, script.contains("return") {
            switch runtime.evaluate("(function(){\(script)})()", variables: variables) {
            case .success(let val): return val
            case .failure(let err): throw err
            }
        }
        switch evaluated {
        case .success(let val): return val
        case .failure(let err): throw err
        }
    }
}
