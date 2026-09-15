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

        // Support @get:{key} or @get:key variable interpolation
        if trimmed.contains("@get:") {
            let pattern = #"(?i)@get:\{?([^}@]*)?\}?"#
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

        let isFullJS = trimmed.hasPrefix("@js:") || trimmed.hasPrefix("<js>")
        if !isFullJS {
            // Check for embedded templates like {{ ... }} or <js> ... </js>
            if (trimmed.contains("{{") && trimmed.contains("}}")) || (trimmed.contains("<js>") && trimmed.contains("</js>")) {
                let runtime = context.jsRuntime(ajaxHandler: { urlText in
                    SynchronousSourceLoader().load(urlText: urlText, source: source)
                })

                var jsVariables: [String: Any] = [
                    "baseUrl": baseUrl,
                    "result": trimmed,
                    "source": source
                ]
                for (k, v) in variables {
                    jsVariables[k] = v
                }

                // Resolve {{ ... }}
                if let regex = try? NSRegularExpression(pattern: #"\{\{([\s\S]*?)\}\}"#) {
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

                // Resolve <js> ... </js>
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

                // Strip trailing ## comment if present
                if let hashRange = trimmed.range(of: "##") {
                    trimmed = String(trimmed[..<hashRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                }

                if !trimmed.hasPrefix("http://") && !trimmed.hasPrefix("https://") {
                    if let baseURLObj = URL(string: baseUrl) {
                        return HtmlRuleExtractor(executionContext: context).absolutize(trimmed, base: baseURLObj)
                    }
                }
                return trimmed
            }

            return rawURL
        }

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
            "result": trimmed,
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
            return rawURL
        case .failure:
            return rawURL
        }
    }
}
