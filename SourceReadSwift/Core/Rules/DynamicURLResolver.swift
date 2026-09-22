import Foundation
import JavaScriptCore

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
        }

        // Support @get:{key} or @get:key or @get:%7Bkey%7D variable interpolation
        if trimmed.lowercased().contains("@get:") {
            let pattern = #"(?i)@get:(?:\{|%7b)?([^%}&@\s]*)?(?:\}|%7d)?"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)).reversed()
                for match in matches {
                    guard let fullRange = Range(match.range(at: 0), in: trimmed),
                          let keyRange = Range(match.range(at: 1), in: trimmed) else { continue }
                    let key = String(trimmed[keyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let val = context.get(key)
                    trimmed.replaceSubrange(fullRange, with: val)
                }
            }
        }

        // Decode percent-encoded template braces: %7B%7B -> {{, %7D%7D -> }}
        trimmed = trimmed
            .replacingOccurrences(of: "%7B%7B", with: "{{", options: .caseInsensitive)
            .replacingOccurrences(of: "%7D%7D", with: "}}", options: .caseInsensitive)

        // Strip accidental double domain concatenation, e.g. `http://domain/http://domain/path`
        if let regex = try? NSRegularExpression(pattern: #"^https?://[^/]+/(https?://.+)$"#) {
            let nsText = trimmed as NSString
            if let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsText.length)),
               match.numberOfRanges > 1,
               let innerRange = Range(match.range(at: 1), in: trimmed) {
                trimmed = String(trimmed[innerRange])
            }
        }

        // Strip preceding URL path if it accidentally prepended a base domain to an embedded JS directive
        if let jsIdx = trimmed.range(of: "/@js:")?.lowerBound {
            trimmed = String(trimmed[trimmed.index(after: jsIdx)...])
        } else if let jsIdx = trimmed.range(of: "/<js>")?.lowerBound {
            trimmed = String(trimmed[trimmed.index(after: jsIdx)...])
        } else if let jsIdx = trimmed.range(of: "\n@js:")?.lowerBound {
            trimmed = String(trimmed[trimmed.index(after: jsIdx)...]).trimmingCharacters(in: .whitespacesAndNewlines)
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
                let nsText = trimmed as NSString
                let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsText.length))
                for match in matches.reversed() {
                    guard match.numberOfRanges > 1,
                          let fullRange = Range(match.range(at: 0), in: trimmed),
                          let codeRange = Range(match.range(at: 1), in: trimmed) else { continue }
                    let script = String(trimmed[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    var evaluatedValue: String? = nil

                    // If script is a JSONPath (starts with $), extract from response JSON or variables
                    if script.hasPrefix("$") {
                        let jsonExtractor = JSONRuleExtractor(executionContext: context)
                        if let bodyStr = jsVariables["body"] as? String ?? jsVariables["result"] as? String,
                           let jsonObj = ResponseFormatDetector.jsonObject(from: bodyStr) {
                            evaluatedValue = jsonExtractor.string(from: jsonObj, rule: script, fallbackKeys: [], variables: jsVariables)
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
                            trimmed.replaceSubrange(fullRange, with: cleanEval)
                        }
                    }
                }
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
                    let nsText = trimmed as NSString
                    let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsText.length))
                    for match in matches.reversed() {
                        guard match.numberOfRanges > 1,
                              let fullRange = Range(match.range(at: 0), in: trimmed),
                              let codeRange = Range(match.range(at: 1), in: trimmed) else { continue }
                        let script = String(trimmed[codeRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let evalResult = runtime.evaluate(script, variables: jsVariables)
                        if case .success(let evaluated) = evalResult {
                            let cleanEval = evaluated.trimmingCharacters(in: .whitespacesAndNewlines)
                            if cleanEval != "undefined" && cleanEval != "null" {
                                trimmed.replaceSubrange(fullRange, with: cleanEval)
                            }
                        }
                    }
                }
            }

            // Strip trailing ## comment if present
            if let hashRange = trimmed.range(of: "##") {
                trimmed = String(trimmed[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            }

            // Clean double domain again after template substitution
            if let regex = try? NSRegularExpression(pattern: #"^https?://[^/]+/(https?://.+)$"#) {
                let nsText = trimmed as NSString
                if let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: nsText.length)),
                   match.numberOfRanges > 1,
                   let innerRange = Range(match.range(at: 1), in: trimmed) {
                    trimmed = String(trimmed[innerRange])
                }
            }

            if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
                if let baseURLObj = URL(string: baseUrl) {
                    return HtmlRuleExtractor(executionContext: context).absolutize(trimmed, base: baseURLObj)
                }
            }
            return trimmed
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
}
