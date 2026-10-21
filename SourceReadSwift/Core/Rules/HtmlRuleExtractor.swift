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
        value(for: key) ?? ""
    }

    func value(for key: String) -> String? {
        values[key.trimmingCharacters(in: .whitespacesAndNewlines)]
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
        try stringList(
            from: root,
            rule: rule,
            fallback: fallback,
            baseUrl: baseUrl,
            variables: variables
        ).joined(separator: "\n")
    }

    /// Legado `AnalyzeByJSoup.getStringList` equivalent.
    ///
    /// Node boundaries are preserved: one selected element yields exactly one
    /// string even when its text contains newlines (for example `@textNodes`
    /// or `<br>`-separated paragraphs).  Only the top-level `&&`, `||` and
    /// `%%` operators merge lists.
    func stringList(
        from root: Element,
        rule: String?,
        fallback: String? = nil,
        baseUrl: URL? = nil,
        variables: [String: Any] = [:]
    ) throws -> [String] {
        let selectedRule = rule ?? fallback
        guard let selectedRule, !selectedRule.isEmpty else { return [] }

        let rawTrimmed = selectedRule.trimmingCharacters(in: .whitespacesAndNewlines)

        // `@put` / `@get` are directives, not selectors or JavaScript.  A rule
        // such as `@put:{token:.token@text}@js:return '@get:{token}'` must
        // materialize the directive before JSCore sees the script text.
        let directiveMaterialized = try applyDirectives(
            root: root,
            rule: rawTrimmed,
            baseUrl: baseUrl,
            variables: variables
        )
        if directiveMaterialized.isDirectValue {
            return directiveMaterialized.text.isEmpty ? [] : [directiveMaterialized.text]
        }
        let trimmed = directiveMaterialized.text
        guard !trimmed.isEmpty else { return [] }

        // Stage 1: Template Interpolation {{...}}
        if trimmed.contains("{{") && trimmed.contains("}}") {
            let interpolated = try interpolateTemplate(trimmed, root: root, baseUrl: baseUrl, variables: variables)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if LegadoRuleResolver().isJavaScriptRule(interpolated) {
                let value = try evaluateJSWithTrailingRegex(rule: interpolated, rootHtml: try root.outerHtml(), rootElement: root, baseUrl: baseUrl, extraVariables: variables)
                return value.isEmpty ? [] : [value]
            }
            return interpolated.isEmpty ? [] : [interpolated]
        }

        if LegadoRuleResolver().isJavaScriptRule(trimmed) {
            let value = try evaluateJSWithTrailingRegex(rule: trimmed, rootHtml: try root.outerHtml(), rootElement: root, baseUrl: baseUrl, extraVariables: variables)
            return value.isEmpty ? [] : [value]
        }

        // Support chained JavaScript rules: Selector@js:script or Selector<js>script</js>
        if let jsRange = trimmed.range(of: "@js:"), jsRange.lowerBound > trimmed.startIndex {
            let value = try evaluateChainedJavaScript(trimmed: trimmed, jsRange: jsRange, root: root, baseUrl: baseUrl, variables: variables)
            return value.isEmpty ? [] : [value]
        }

        if let jsStart = trimmed.range(of: "<js>"), jsStart.lowerBound > trimmed.startIndex {
            let value = try evaluateChainedJavaScript(trimmed: trimmed, jsRange: jsStart, root: root, baseUrl: baseUrl, variables: variables)
            return value.isEmpty ? [] : [value]
        }

        // Legado splits a rule on the first top-level `&&`, `||` or `%%`
        // in source order.  Checking `||` before `&&` would give
        // `a&&b||c` the wrong precedence and drop the `&&` branch.
        if let operation = RuleOperatorSplitter.firstOperator(in: trimmed) {
            let parts = operation.parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            switch operation.op {
            case "&&":
                // `&&` concatenates every branch list in source order.
                var merged: [String] = []
                for part in parts {
                    let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedPart.hasPrefix("$.") || trimmedPart.hasPrefix("@json:") {
                        continue
                    }
                    merged.append(contentsOf: try stringList(
                        from: root,
                        rule: trimmedPart,
                        fallback: nil,
                        baseUrl: baseUrl,
                        variables: variables
                    ))
                }
                return merged
            case "||":
                for alternative in parts {
                    let trimmedAlt = alternative.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedAlt.hasPrefix("$.") || trimmedAlt.hasPrefix("@json:") {
                        continue
                    }
                    do {
                        let values = try stringList(
                            from: root,
                            rule: trimmedAlt,
                            fallback: nil,
                            baseUrl: baseUrl,
                            variables: variables
                        )
                        if !values.isEmpty { return values }
                    } catch {
                        continue
                    }
                }
                return []
            case "%%":
                let lists = try parts
                    .map { try stringList(from: root, rule: $0, fallback: nil, baseUrl: baseUrl, variables: variables) }
                    .filter { !$0.isEmpty }
                return interleave(lists)
            default:
                break
            }
        }

        return try valuesForSingleRule(
            from: root,
            rule: trimmed,
            baseUrl: baseUrl,
            variables: variables
        )
    }

    private func evaluateChainedJavaScript(
        trimmed: String,
        jsRange: Range<String.Index>,
        root: Element,
        baseUrl: URL?,
        variables: [String: Any]
    ) throws -> String {
        let prefix = String(trimmed[..<jsRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let script = String(trimmed[jsRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let elements = (try? self.select(
            from: root,
            rule: prefix,
            baseUrl: baseUrl,
            variables: variables
        )) ?? []
        if let first = elements.first {
            var chainedVariables = variables
            let baseStr = baseUrl?.absoluteString ?? ""
            chainedVariables["result"] = elements.count == 1 ? LegadoElementBridge(element: first, baseURL: baseStr) : LegadoElementsBridge(elements: elements, baseURL: baseStr)
            let extractedHtml = (try? first.outerHtml()) ?? ""
            chainedVariables["src"] = extractedHtml
            chainedVariables["html"] = extractedHtml
            return try evaluateJSWithTrailingRegex(rule: script, rootHtml: extractedHtml, rootElement: first, baseUrl: baseUrl, extraVariables: chainedVariables)
        } else {
            let extracted = try self.value(from: root, rule: prefix, fallback: nil, baseUrl: baseUrl, variables: variables)
            var chainedVariables = variables
            chainedVariables["result"] = extracted
            chainedVariables["src"] = extracted
            chainedVariables["html"] = extracted
            return try evaluateJSWithTrailingRegex(rule: script, rootHtml: extracted, rootElement: nil, baseUrl: baseUrl, extraVariables: chainedVariables)
        }
    }
    private func valuesForSingleRule(
        from root: Element,
        rule: String,
        baseUrl: URL?,
        variables: [String: Any] = [:]
    ) throws -> [String] {
        let materialized = try applyDirectives(
            root: root,
            rule: rule,
            baseUrl: baseUrl,
            variables: variables
        )
        let materializedRule = materialized.text
        if materializedRule.isEmpty {
            return []
        }
        // A rule such as `@put:{host:.host@text}@get:{host}/book/1` is a
        // directive template, not a CSS selector.  `applyDirectives` resolves
        // it to the final string and marks it, so the value must not be fed
        // back into selector parsing.
        if materialized.isDirectValue {
            return [materializedRule]
        }

        if let jsonRange = materializedRule.range(of: "@json:") {
            let left = String(materializedRule[..<jsonRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(materializedRule[jsonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawText: String
            if !left.isEmpty {
                rawText = (try? valuesForSingleRule(
                    from: root,
                    rule: left,
                    baseUrl: baseUrl,
                    variables: variables
                ))?.joined(separator: "\n") ?? ""
            } else {
                rawText = (try? root.outerHtml()) ?? ""
            }
            if let obj = ResponseFormatDetector.jsonObject(from: rawText) {
                // The HTML extractor and the nested JSON extractor must share
                // one context: `@put` values written while parsing HTML are
                // visible to JSON `@get` (and the reverse) in the same stage.
                let jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
                if let val = jsonExtractor.value(from: obj, path: right, variables: variables) {
                    if let arr = val as? [Any] {
                        return arr.map { jsonExtractor.stringify($0) }.filter { !$0.isEmpty }
                    }
                    let str = jsonExtractor.stringify(val)
                    return str.isEmpty ? [] : [str]
                }
            }
            return []
        }

        // Try XPath translator first
        if let xpathSplit = XPathRuleTranslator.valueRule(materializedRule) {
            let targets = try select(
                from: root,
                rule: xpathSplit.selector,
                baseUrl: baseUrl,
                variables: variables
            )
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
        let targets = try select(
            from: root,
            rule: split.selector,
            baseUrl: baseUrl,
            variables: variables
        )
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

    func select(
        from root: Element,
        rule: String,
        baseUrl: URL? = nil,
        variables: [String: Any] = [:]
    ) throws -> [Element] {
        let materializedRule = try applyDirectives(
            root: root,
            rule: rule,
            baseUrl: baseUrl,
            variables: variables
        ).text
        if materializedRule.isEmpty {
            return [root]
        }

        var isReversed = false
        var workingRule = materializedRule.trimmingCharacters(in: .whitespacesAndNewlines)
        if workingRule.hasPrefix("-") {
            isReversed = true
            workingRule = String(workingRule.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if workingRule.hasPrefix("+") {
            workingRule = String(workingRule.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func finish(_ elements: [Element]) -> [Element] {
            isReversed ? elements.reversed() : elements
        }

        // Handle JS rules inside select
        if workingRule.hasPrefix("@js:") {
            let script = String(workingRule.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            if let jsElements = executeJSElements(script: script, root: root, baseUrl: baseUrl, variables: variables) {
                return finish(jsElements)
            }
        } else if workingRule.hasPrefix("<js>"), let endRange = workingRule.range(of: "</js>") {
            let start = workingRule.index(workingRule.startIndex, offsetBy: 4)
            let script = String(workingRule[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remaining = String(workingRule[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if remaining.isEmpty {
                if let jsElements = executeJSElements(script: script, root: root, baseUrl: baseUrl, variables: variables) {
                    return finish(jsElements)
                }
            } else {
                let htmlOutput = (try? evaluateJS(rule: script, rootHtml: try root.outerHtml(), baseUrl: baseUrl, extraVariables: variables)) ?? ""
                if !htmlOutput.isEmpty, let doc = try? SwiftSoup.parse(htmlOutput, baseUrl?.absoluteString ?? "") {
                    let subElements = try select(
                        from: doc,
                        rule: remaining,
                        baseUrl: baseUrl,
                        variables: variables
                    )
                    return finish(subElements)
                }
            }
        } else if let jsStartRange = workingRule.range(of: "<js>"), let jsEndRange = workingRule.range(of: "</js>") {
            let prefix = String(workingRule[..<jsStartRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let script = String(workingRule[jsStartRange.upperBound..<jsEndRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let initialElements = try select(
                from: root,
                rule: prefix,
                baseUrl: baseUrl,
                variables: variables
            )
            if let jsElements = executeJSElements(script: script, elements: initialElements, root: root, baseUrl: baseUrl, variables: variables) {
                return finish(jsElements)
            }
        }

        if let operation = RuleOperatorSplitter.firstOperator(in: workingRule) {
            let parts = operation.parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            switch operation.op {
            case "&&":
                var merged: [Element] = []
                for part in parts {
                    let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedPart.hasPrefix("$.") || trimmedPart.hasPrefix("@json:") {
                        continue
                    }
                    merged.append(contentsOf: try select(
                        from: root,
                        rule: trimmedPart,
                        baseUrl: baseUrl,
                        variables: variables
                    ))
                }
                return finish(merged)
            case "||":
                for part in parts {
                    let trimmedPart = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedPart.hasPrefix("$.") || trimmedPart.hasPrefix("@json:") {
                        continue
                    }
                    do {
                        let elements = try select(
                            from: root,
                            rule: trimmedPart,
                            baseUrl: baseUrl,
                            variables: variables
                        )
                        if !elements.isEmpty { return finish(elements) }
                    } catch {
                        continue
                    }
                }
                return []
            case "%%":
                let lists = try parts
                    .map { try select(from: root, rule: $0, baseUrl: baseUrl, variables: variables) }
                    .filter { !$0.isEmpty }
                return finish(interleave(lists))
            default:
                break
            }
        }

        if let xpathSelector = XPathRuleTranslator.selectorRule(workingRule) {
            let indexed = parseIndexedSelector(xpathSelector)
            let elements: [Element]
            do {
                elements = try root.select(indexed.selector).array()
            } catch {
                return []
            }
            var filtered = elements
            if let excl = indexed.excludeIndex {
                let norm = excl >= 0 ? excl : filtered.count + excl
                if filtered.indices.contains(norm) { filtered.remove(at: norm) }
            }
            if let index = indexed.index {
                let normalized = index >= 0 ? index : filtered.count + index
                guard filtered.indices.contains(normalized) else { return [] }
                filtered = [filtered[normalized]]
            }
            return finish(filtered)
        }

        let steps = LegadoDefaultRuleTranslator.translateSelectorSteps(workingRule)
        if !steps.isEmpty {
            let executed = LegadoDefaultRuleTranslator.executeSteps(steps, on: root)
            if !executed.isEmpty {
                return finish(executed)
            }
        }

        let selector = cleanCSS(workingRule)
        guard !selector.isEmpty else { return finish([root]) }
        let indexed = parseIndexedSelector(selector)
        let elements: [Element]
        do {
            elements = try root.select(indexed.selector).array()
        } catch {
            return []
        }
        var filtered = elements
        if let excl = indexed.excludeIndex {
            let norm = excl >= 0 ? excl : filtered.count + excl
            if filtered.indices.contains(norm) { filtered.remove(at: norm) }
        }
        if let index = indexed.index {
            let normalized = index >= 0 ? index : filtered.count + index
            guard filtered.indices.contains(normalized) else { return [] }
            filtered = [filtered[normalized]]
        }
        return finish(filtered)
    }

    private func executeJSElements(
        script: String,
        elements: [Element]? = nil,
        root: Element,
        baseUrl: URL?,
        variables: [String: Any] = [:]
    ) -> [Element]? {
        let source = variables["source"] as? BookSource
        let runtime = executionContext.jsRuntime(ajaxHandler: { urlText in
            if let source {
                return SynchronousSourceLoader().load(urlText: urlText, source: source)
            }
            return ""
        })
        var jsVariables: [String: Any] = [
            "baseUrl": baseUrl?.absoluteString ?? "",
            "src": (try? root.outerHtml()) ?? "",
            "html": (try? root.outerHtml()) ?? ""
        ]
        // Element rules run in the same variable scope as value rules:
        // `keyword`, `page`, `book`, `source` and earlier `@put` values must
        // stay visible when a source mixes `@js:` selectors with JS values.
        for (key, value) in variables {
            jsVariables[key] = value
        }
        // `@put` values written by earlier rules live in the source-scoped
        // context, not in the caller's `variables` dictionary.  Legado JS
        // reads them through `java.get`; expose the snapshot as bare variables
        // too, without overriding real inputs.
        for (key, value) in executionContext.persistentSnapshot() where jsVariables[key] == nil {
            jsVariables[key] = value
        }
        if let elements {
            jsVariables["result"] = LegadoElementsBridge(elements: elements, baseURL: baseUrl?.absoluteString ?? "")
        } else {
            jsVariables["result"] = LegadoElementsBridge(elements: [root], baseURL: baseUrl?.absoluteString ?? "")
        }
        switch runtime.evaluateElementResult(script, variables: jsVariables) {
        case .failure:
            return nil
        case .success(let captured):
            guard let jsValue = captured else { return nil }
            if let bridge = jsValue.toObject() as? LegadoElementsBridge {
                return bridge.elements
            }
            if let bridge = jsValue.toObject() as? LegadoElementBridge {
                return [bridge.element]
            }
            if let array = jsValue.toArray() {
                var foundElements: [Element] = []
                for item in array {
                    if let bridge = item as? LegadoElementBridge {
                        foundElements.append(bridge.element)
                    } else if let bridge = item as? LegadoElementsBridge {
                        foundElements.append(contentsOf: bridge.elements)
                    } else if let el = item as? Element {
                        foundElements.append(el)
                    }
                }
                if !foundElements.isEmpty { return foundElements }
            }
            // A rule may replace `result` with an HTML string; keep the
            // legacy parse path for that shape only.
            if jsValue.isString, let html = jsValue.toString(), !html.isEmpty,
               let doc = try? SwiftSoup.parse(html, baseUrl?.absoluteString ?? "") {
                return doc.body()?.children().array()
            }
            return nil
        }
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

    private func parseIndexedSelector(_ selector: String) -> (selector: String, index: Int?, excludeIndex: Int?) {
        let trimmed = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exclMatch = trimmed.range(of: #"(?:\[!(-?\d+)\]|!(-?\d+))$"#, options: .regularExpression) {
            let matchedStr = String(trimmed[exclMatch])
            let digits = matchedStr.replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "!", with: "")
            let sel = String(trimmed[..<exclMatch.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (sel, nil, Int(digits))
        }
        if let idxMatch = trimmed.range(of: #"(?:\[(-?\d+)\]|@(-?\d+)|:eq\((-?\d+)\))$"#, options: .regularExpression) {
            let matchedStr = String(trimmed[idxMatch])
            let clean = matchedStr
                .replacingOccurrences(of: "[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: "@", with: "")
                .replacingOccurrences(of: ":eq(", with: "")
                .replacingOccurrences(of: ")", with: "")
            let sel = String(trimmed[..<idxMatch.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (sel, Int(clean), nil)
        }
        return (trimmed, nil, nil)
    }

    private func applyRegexTransforms(_ rawParts: ArraySlice<String>, to value: String) -> String {
        RuleTransformParser.apply(
            RuleTransformParser.transform(fromTrailingParts: rawParts),
            to: value
        )
    }

    /// Result of applying `@put` / `@get` to one rule.
    private struct MaterializedDirectiveRule {
        let text: String
        /// True when the rule was a directive template (`@get:{key}` plus an
        /// optional suffix) whose final text is a value, not a selector.
        let isDirectValue: Bool
    }

    private func applyDirectives(
        root: Element,
        rule: String,
        baseUrl: URL?,
        variables: [String: Any] = [:]
    ) throws -> MaterializedDirectiveRule {
        var output = rule
        let putDirectives = extractPutDirectives(from: output)
        for directive in putDirectives {
            let value = try value(
                from: root,
                rule: directive.valueRule,
                fallback: nil,
                baseUrl: baseUrl,
                variables: variables
            )
            directiveStore.put(directive.key, value: value)
            executionContext.put(value, for: directive.key)
        }
        output = removePutDirectives(from: output)
        let afterPuts = output.trimmingCharacters(in: .whitespacesAndNewlines)
        // A leading `@get` makes the whole rule a value template.  Legado
        // allows literal suffixes (`@get:{host}/book/1`) and regex transforms
        // (`@get:{url}##pattern##replacement`) after the directive.
        if afterPuts.lowercased().hasPrefix("@get:"),
           let resolved = resolveLeadingGetDirective(in: afterPuts) {
            return MaterializedDirectiveRule(text: resolved, isDirectValue: true)
        }
        output = replaceGetDirectives(in: output)
        return MaterializedDirectiveRule(
            text: output.trimmingCharacters(in: .whitespacesAndNewlines),
            isDirectValue: false
        )
    }

    /// Resolves `@get:{key}` / `@get:key` when it starts a rule.  The suffix
    /// is either a `##` transform chain or literal text (URL suffix/template);
    /// both apply to the stored value instead of becoming a CSS selector.
    private func resolveLeadingGetDirective(in rule: String) -> String? {
        let markerEnd = rule.index(rule.startIndex, offsetBy: 5)
        var after = markerEnd
        while after < rule.endIndex, rule[after].isWhitespace {
            after = rule.index(after: after)
        }
        let key: String
        let remainder: String
        if after < rule.endIndex, rule[after] == "{" {
            guard let closing = RuleDirectiveParser.matchingBrace(in: rule, from: after) else {
                return nil
            }
            key = RuleDirectiveParser.unquote(
                String(rule[rule.index(after: after)..<closing])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
            remainder = String(rule[rule.index(after: closing)...])
        } else {
            var cursor = after
            while cursor < rule.endIndex, isBareDirectiveKeyCharacter(rule[cursor]) {
                cursor = rule.index(after: cursor)
            }
            key = RuleDirectiveParser.unquote(
                String(rule[after..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines)
            )
            remainder = String(rule[cursor...])
        }
        guard !key.isEmpty else { return nil }
        let stored = storedDirectiveValue(for: key)
        let trailing = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if trailing.isEmpty { return stored }
        if trailing.hasPrefix("##") {
            let parts = trailing.components(separatedBy: "##")
            return applyRegexTransforms(parts.dropFirst(), to: stored)
        }
        // `@js:`, `<js>`, `@text`, `@href`, ... are rule continuations,
        // not literal suffixes; let the normal rule pipeline handle them.
        if trailing.hasPrefix("@") || trailing.hasPrefix("<js>") {
            return nil
        }
        return stored + replaceGetDirectives(in: remainder)
    }

    private func isBareDirectiveKeyCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == "$"
    }

    private func extractPutDirectives(from rule: String) -> [(key: String, valueRule: String)] {
        RuleDirectiveParser.putPairs(in: rule).filter { !$0.valueRule.isEmpty }
    }

    private func removePutDirectives(from rule: String) -> String {
        RuleDirectiveParser.removingPuts(from: rule)
    }

    private func replaceGetDirectives(in rule: String) -> String {
        RuleDirectiveParser.replacingGets(in: rule) { storedDirectiveValue(for: $0) }
    }

    /// Reads `@put` values from the current stage first, then from the
    /// source-scoped persistent state so a later stage can use a value that
    /// was stored while parsing search results or a book detail page.
    private func storedDirectiveValue(for key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = directiveStore.value(for: trimmed) { return value }
        if let value = executionContext.storedValue(for: trimmed) {
            return RuleExecutionContext.bridgeString(value)
        }
        return ""
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
        var cleaned = output.replacingOccurrences(of: "&&", with: " ")
        cleaned = RuleDirectiveParser.removingPuts(from: cleaned)
        cleaned = RuleDirectiveParser.replacingGets(in: cleaned) { _ in "" }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
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
        guard let regex = try? NSRegularExpression(pattern: #"\{\{\s*([^{}]+)\s*\}\}"#) else { return template }
        let mText = NSMutableString(string: template)
        let matches = regex.matches(in: template, range: NSRange(location: 0, length: mText.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let keyRange = match.range(at: 1)
            let fullRange = match.range(at: 0)
            let expr = mText.substring(with: keyRange).trimmingCharacters(in: .whitespacesAndNewlines)
            var val = ""
            if expr.hasPrefix("@@") {
                let subRule = String(expr.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
                val = (try? self.value(from: root, rule: subRule, fallback: nil, baseUrl: baseUrl, variables: variables)) ?? ""
            } else if expr.hasPrefix("@css:") || expr.hasPrefix("@xpath:") || expr.hasPrefix("class.") || expr.hasPrefix("tag.") || expr.hasPrefix("id.") || expr.hasPrefix(".") || expr.hasPrefix("#") {
                val = (try? self.value(from: root, rule: expr, fallback: nil, baseUrl: baseUrl, variables: variables)) ?? ""
            } else if expr.hasPrefix("$.") || expr.hasPrefix("@json:") {
                let jsonPath = expr.hasPrefix("@json:") ? String(expr.dropFirst(6)) : expr
                let jsonExtractor = JSONRuleExtractor(executionContext: executionContext)
                if let obj = ResponseFormatDetector.jsonObject(from: (try? root.outerHtml()) ?? ""),
                   let extracted = jsonExtractor.value(from: obj, path: jsonPath, variables: variables) {
                    val = jsonExtractor.stringify(extracted)
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
            mText.replaceCharacters(in: fullRange, with: val)
        }
        return mText as String
    }

    private func evaluateJSWithTrailingRegex(
        rule: String,
        rootHtml: String,
        rootElement: Element? = nil,
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
                if !parts.isEmpty {
                    script = String(script[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                    trailingRegexParts = Array(parts)
                }
            }
        }

        let jsResult: String
        if script.isEmpty {
            jsResult = rootHtml
        } else {
            jsResult = try evaluateJS(rule: script, rootHtml: rootHtml, rootElement: rootElement, baseUrl: baseUrl, extraVariables: extraVariables)
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
                return try evaluateJSWithTrailingRegex(rule: chained, rootHtml: currentResult, rootElement: nil, baseUrl: baseUrl, extraVariables: chainedVariables)
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
        rootElement: Element? = nil,
        baseUrl: URL?,
        extraVariables: [String: Any]
    ) throws -> String {
        var script = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if script.hasPrefix("@js:") {
            script = String(script.dropFirst(4))
        } else if script.hasPrefix("<js>") && script.hasSuffix("</js>") {
            script = String(script.dropFirst(4).dropLast(5))
        }

        let source = extraVariables["source"] as? BookSource
        let runtime = executionContext.jsRuntime(ajaxHandler: { urlText in
            if let source {
                return SynchronousSourceLoader().load(urlText: urlText, source: source)
            }
            return ""
        })

        let baseStr = baseUrl?.absoluteString ?? ""
        var variables: [String: Any] = [
            "html": rootHtml,
            "src": rootHtml,
            "baseUrl": baseStr
        ]
        if let rootElement {
            variables["result"] = LegadoElementBridge(element: rootElement, baseURL: baseStr)
        } else {
            variables["result"] = rootHtml
        }
        for (k, v) in extraVariables {
            variables[k] = v
        }
        for (key, value) in executionContext.persistentSnapshot() where variables[key] == nil {
            variables[key] = value
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
