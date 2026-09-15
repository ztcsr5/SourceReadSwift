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

        let isJS = trimmed.hasPrefix("@js:") || trimmed.hasPrefix("<js>")
        guard isJS else { return rawURL }

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
