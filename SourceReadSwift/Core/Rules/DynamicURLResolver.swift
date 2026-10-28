import Foundation
import JavaScriptCore
import SwiftSoup

/// Resolves dynamic `@js:` or `<js>` expressions in URLs (such as `bookUrl`, `tocUrl`, `nextTocUrl`)
/// before making network requests, preventing unparsed JS code from being appended to base domains.
struct DynamicURLResolver {
    static func resolve(
        _ rawURL: String,
        baseUrl: String,
        source: BookSource,
        variables: [String: Any] = [:],
        context: RuleExecutionContext
    ) -> String {
        var trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return rawURL }

        // Strip leading @json: if present
        if trimmed.hasPrefix("@json:") {
            trimmed = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
        }

        // Support @get:{key} or @get:key or @get:%7Bkey%7D variable interpolation
        if trimmed.lowercased().contains("@get:") {
            let pattern = #"(?i)@get:(?:\{|%7b)?([^%}&@\s]*)?(?:\}|%7d)?"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let mText = NSMutableString(string: trimmed)
                let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: mText.length))
                for match in matches.reversed() {
                    guard match.numberOfRanges > 1 else { continue }
                    let key = mText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let val = context.get(key)
                    mText.replaceCharacters(in: match.range(at: 0), with: val)
                }
                trimmed = mText as String
            }
        }

        // Decode percent-encoded template braces: %7B%7B -> {{, %7D%7D -> }}
        trimmed = trimmed
            .replacingOccurrences(of: "%7B%7B", with: "{{", options: .caseInsensitive)
            .replacingOccurrences(of: "%7D%7D", with: "}}", options: .caseInsensitive)

        // Legado rules can span multiple lines when a template or JSONPath is
        // followed by an `@js:` segment on the next line (for example
        // `$.book_id\n@js:\n"https://.../"+result`).  Only collapse a plain
        // multi-line URL; never truncate a rule that carries script or
        // template semantics.
        let carriesRuleSyntax = trimmed.contains("@js:")
            || trimmed.contains("<js>")
            || trimmed.contains("{{")
            || trimmed.lowercased().contains("@get:")
        if !carriesRuleSyntax, trimmed.contains("\n") || trimmed.contains("\r") {
            if let firstLine = trimmed.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Strip accidental double domain concatenation, e.g. `http://domain/http://domain/path` or `http://domainhttp://domain/path`
        if (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")) && trimmed.count > 8 {
            let searchStart = trimmed.index(trimmed.startIndex, offsetBy: 7)
            if let secondSchemeRange = trimmed.range(of: "https?://", options: .regularExpression, range: searchStart..<trimmed.endIndex) {
                trimmed = String(trimmed[secondSchemeRange.lowerBound...])
            }
        }

        // Strip preceding URL path if it accidentally prepended a base domain to an embedded JS directive
        if let jsRange = trimmed.range(of: "/@js:") {
            trimmed = String(trimmed[jsRange.lowerBound...].dropFirst())
        } else if let jsRange = trimmed.range(of: "/<js>") {
            trimmed = String(trimmed[jsRange.lowerBound...].dropFirst())
        }

        // 1. Resolve embedded {{ ... }} templates FIRST (even inside @js: blocks, like params={'id':{{$.id}}})
        if trimmed.contains("{{") && trimmed.contains("}}") {
            let runtime = context.jsRuntime(ajaxHandler: { urlText in
                SynchronousSourceLoader().load(urlText: urlText, source: source)
            })

            var jsVariables: [String: Any] = [
                "baseUrl": baseUrl,
                "result": variables["result"] ?? variables["body"] ?? "",
                "source": source
            ]
            for (k, v) in variables {
                jsVariables[k] = v
            }

            if let regex = try? NSRegularExpression(pattern: #"\{\{([\s\S]*?)\}\}"#) {
                let mText = NSMutableString(string: trimmed)
                let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: mText.length))
                for match in matches.reversed() {
                    guard match.numberOfRanges > 1 else { continue }
                    let script = mText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    var evaluatedValue: String? = nil

                    // If script is a JSONPath (starts with $), extract from response JSON or variables
                    if script.hasPrefix("$") {
                        let jsonExtractor = JSONRuleExtractor(executionContext: context)
                        var targetObject: Any? = nil
                        if let dict = jsVariables["result"] as? [String: Any] {
                            targetObject = dict
                        } else if let arr = jsVariables["result"] as? [Any] {
                            targetObject = arr
                        } else if let dict = jsVariables["data"] as? [String: Any] {
                            targetObject = dict
                        } else if let dict = jsVariables["body"] as? [String: Any] {
                            targetObject = dict
                        } else if let bodyStr = jsVariables["body"] as? String ?? jsVariables["result"] as? String {
                            targetObject = ResponseFormatDetector.jsonObject(from: bodyStr)
                        } else if let dict = jsVariables["book"] as? [String: Any] {
                            targetObject = dict
                        }

                        if let targetObject {
                            evaluatedValue = jsonExtractor.string(from: targetObject, rule: script, fallbackKeys: [], variables: jsVariables)
                            // Fallback to recursive scan ($..) if top-level property not found and rule uses single dot ($.prop)
                            if evaluatedValue == nil && script.hasPrefix("$.") && !script.hasPrefix("$..") {
                                let deepRule = "$.." + script.dropFirst(2)
                                evaluatedValue = jsonExtractor.string(from: targetObject, rule: String(deepRule), fallbackKeys: [], variables: jsVariables)
                            }
                        } else if let dict = jsVariables["book"] as? [String: Any] {
                            evaluatedValue = jsonExtractor.string(from: dict, rule: script, fallbackKeys: [], variables: jsVariables)
                        }
                    }

                    if evaluatedValue == nil {
                        let evalResult = runtime.evaluate(script, variables: jsVariables)
                        if case .success(let evaluated) = evalResult {
                            evaluatedValue = evaluated
                        }
                    }

                    if let evaluated = evaluatedValue {
                        let cleanEval = evaluated.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !cleanEval.isEmpty && cleanEval != "undefined" && cleanEval != "null" {
                            mText.replaceCharacters(in: match.range(at: 0), with: cleanEval)
                        }
                    }
                }
                trimmed = mText as String
            }
        }

        // 2. If it is NOT a full JavaScript rule (@js: or <js>...</js>)
        let isFullJS = trimmed.hasPrefix("@js:") || trimmed.hasPrefix("<js>")
        if !isFullJS {
            // Check for embedded <js> ... </js>
            if trimmed.contains("<js>") && trimmed.contains("</js>") {
                let runtime = context.jsRuntime(ajaxHandler: { urlText in
                    SynchronousSourceLoader().load(urlText: urlText, source: source)
                })

                var jsVariables: [String: Any] = [
                    "baseUrl": baseUrl,
                    "result": variables["result"] ?? variables["body"] ?? "",
                    "source": source
                ]
                for (k, v) in variables {
                    jsVariables[k] = v
                }

                if let regex = try? NSRegularExpression(pattern: #"<js>([\s\S]*?)</js>"#) {
                    let mText = NSMutableString(string: trimmed)
                    let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: mText.length))
                    for match in matches.reversed() {
                        guard match.numberOfRanges > 1 else { continue }
                        let script = mText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                        let evalResult = runtime.evaluate(script, variables: jsVariables)
                        if case .success(let evaluated) = evalResult {
                            let cleanEval = evaluated.trimmingCharacters(in: .whitespacesAndNewlines)
                            if cleanEval != "undefined" && cleanEval != "null" {
                                mText.replaceCharacters(in: match.range(at: 0), with: cleanEval)
                            }
                        }
                    }
                    trimmed = mText as String
                }
            }

            // A normal URL/template or JSONPath followed by an inline
            // `@js:` chain (Legado `makeUpRule` semantics).  Evaluate the
            // left side first, expose it as `result`, then run the script.
            if let jsRange = trimmed.range(of: "@js:") {
                let left = String(trimmed[..<jsRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var script = String(trimmed[jsRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                var trailingParts: [String] = []
                if let hashRange = script.range(of: "##") {
                    trailingParts = Array(script[hashRange.lowerBound...]
                        .components(separatedBy: "##")
                        .dropFirst())
                    script = String(script[..<hashRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }

                let runtime = context.jsRuntime(ajaxHandler: { urlText in
                    SynchronousSourceLoader().load(urlText: urlText, source: source)
                })
                var jsVariables: [String: Any] = [
                    "baseUrl": baseUrl,
                    "source": source
                ]
                for (k, v) in variables {
                    jsVariables[k] = v
                }

                var chainedResult: Any = variables["result"] ?? variables["body"] ?? ""
                if !left.isEmpty {
                    if left.hasPrefix("$") || left.lowercased().hasPrefix("@json:") {
                        if let target = Self.jsonTarget(from: variables),
                           let value = JSONRuleExtractor(executionContext: context)
                            .value(from: target, path: left, variables: variables) {
                            chainedResult = value
                        } else {
                            chainedResult = ""
                        }
                    } else {
                        // Legado evaluates a bare left-hand rule (for example
                        // `gid@js:...`) against the current document before
                        // running the script.  Treating it as a literal leaves
                        // `result` equal to the rule text and silently builds a
                        // broken URL such as `data={"gid":gid}`.
                        var resolvedLeft: Any?
                        if let target = Self.jsonTarget(from: variables) {
                            let extractor = JSONRuleExtractor(executionContext: context)
                            if let value = extractor.value(from: target, path: left, variables: variables) {
                                resolvedLeft = value
                            } else if !left.contains("$"),
                                      let value = extractor.value(from: target, path: "$." + left, variables: variables) {
                                // Legado treats a bare left side (`gid@js:...`)
                                // as a field of the current document.  Our path
                                // parser needs the `$.` prefix, otherwise the
                                // literal rule text ends up inside the URL
                                // (`data={"gid":gid}`) and the API answers 0 bytes.
                                resolvedLeft = value
                            }
                        }
                        if resolvedLeft == nil,
                           let html = (variables["html"] as? String) ?? (variables["body"] as? String),
                           let baseURLObj = URL(string: baseUrl),
                           let document = try? SwiftSoup.parse(html),
                           let value = try? HtmlRuleExtractor(executionContext: context)
                            .value(from: document, rule: left, fallback: nil, baseUrl: baseURLObj, variables: variables) {
                            resolvedLeft = value
                        }
                        chainedResult = resolvedLeft ?? left
                    }
                }
                jsVariables["result"] = chainedResult

                guard case .success(let evaluatedRaw) = runtime.evaluate(script, variables: jsVariables) else {
                    return ""
                }
                var evaluated = evaluatedRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trailingParts.isEmpty,
                   let transform = RuleTransformParser.transform(fromTrailingParts: trailingParts[...]) {
                    evaluated = RuleTransformParser.apply(transform, to: evaluated)
                }
                if evaluated.isEmpty || evaluated == "undefined" || evaluated == "null" || evaluated == "#" {
                    return ""
                }
                if evaluated.lowercased().hasPrefix("javascript:") {
                    return ""
                }
                if let baseURLObj = URL(string: baseUrl) {
                    return HtmlRuleExtractor(executionContext: context).absolutize(evaluated, base: baseURLObj)
                }
                return evaluated
            }

            // Strip trailing ## comment if present
            if let hashRange = trimmed.range(of: "##") {
                trimmed = String(trimmed[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Clean double domain again after template substitution
            if let regex = try? NSRegularExpression(pattern: #"^https?://[^/]+/(https?://.+)$"#) {
                let nsText = trimmed as NSString
                if let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsText.length)),
                   match.numberOfRanges > 1 {
                    trimmed = nsText.substring(with: match.range(at: 1))
                }
            }

            let (plainURL, directiveSuffix) = SearchURLResolver.splitURLAndDirectiveSuffix(trimmed)
            return Self.absolutize(plainURL, baseUrl: baseUrl) + directiveSuffix
        }

        // 3. Handle full JavaScript rule
        let script: String
        var chainedSubrule: String? = nil
        if trimmed.hasPrefix("@js:") {
            script = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.hasPrefix("<js>"), let endRange = trimmed.range(of: "</js>") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
            script = String(trimmed[start..<endRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let remaining = String(trimmed[endRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !remaining.isEmpty {
                chainedSubrule = remaining
            }
        } else {
            script = trimmed
        }

        let runtime = context.jsRuntime(ajaxHandler: { urlText in
            SynchronousSourceLoader().load(urlText: urlText, source: source)
        })

        var jsVariables: [String: Any] = [
            "baseUrl": baseUrl,
            "result": variables["result"] ?? variables["body"] ?? "",
            "source": source
        ]
        for (k, v) in variables {
            jsVariables[k] = v
        }

        let evalResult = runtime.evaluate(script, variables: jsVariables)
        switch evalResult {
        case .success(let evaluated):
            var resultText = evaluated.trimmingCharacters(in: .whitespacesAndNewlines)
            if let chained = chainedSubrule, !chained.isEmpty {
                if chained.hasPrefix("$.") || chained.hasPrefix("@json:") {
                    var jsonTarget: Any = resultText
                    if let data = resultText.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                        jsonTarget = parsed
                    }
                    let jsonExtractor = JSONRuleExtractor(executionContext: context)
                    if let val = jsonExtractor.value(from: jsonTarget, path: chained, variables: variables) {
                        resultText = jsonExtractor.stringify(val).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
            if resultText.lowercased().hasPrefix("javascript:") || resultText == "#" {
                return ""
            }
            if !resultText.isEmpty && resultText != "undefined" && resultText != "null" {
                // If the JS returned a relative path, absolutize against baseUrl
                if let baseURLObj = URL(string: baseUrl) {
                    return HtmlRuleExtractor(executionContext: context).absolutize(resultText, base: baseURLObj)
                }
                return resultText
            }
            return ""
        case .failure:
            return ""
        }
    }

    /// Picks the object that JSONPath segments in a URL rule should run
    /// against.  Parsers usually pass a decoded object as `result`, but some
    /// call sites only provide the raw response body.
    /// Legado's `NetworkUtils.getAbsoluteURL`: a source may give a bare path
    /// (`/search.html?q=...`) or a protocol-relative URL.  Resolve it against
    /// the source URL before the request is built; otherwise URLSession rejects
    /// the empty scheme and the whole search dies with
    /// "不支持的 URL 协议 无".
    static func absolutize(_ raw: String, baseUrl: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return raw }
        let lower = value.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://")
            || lower.hasPrefix("data:") || lower.hasPrefix("file:")
            || lower.hasPrefix("content:") || lower.hasPrefix("javascript:") {
            return value
        }
        guard let base = URL(string: baseUrl) else { return value }
        if value.hasPrefix("//") {
            return (base.scheme ?? "https") + ":" + value
        }
        if let resolved = URL(string: value, relativeTo: base)?.absoluteURL.absoluteString,
           !resolved.isEmpty {
            return resolved
        }
        return value
    }

    private static func jsonTarget(from variables: [String: Any]) -> Any? {
        if let value = variables["result"], JSONSerialization.isValidJSONObject(value) {
            return value
        }
        if let value = variables["data"], JSONSerialization.isValidJSONObject(value) {
            return value
        }
        if let value = variables["body"], JSONSerialization.isValidJSONObject(value) {
            return value
        }
        if let body = variables["body"] as? String ?? variables["result"] as? String,
           let parsed = ResponseFormatDetector.jsonObject(from: body) {
            return parsed
        }
        if let book = variables["book"] as? [String: Any] {
            return book
        }
        return nil
    }
}
