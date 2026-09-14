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
        if trimmed.hasPrefix("@js:") {
            script = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if trimmed.hasPrefix("<js>") && trimmed.contains("</js>") {
            let start = trimmed.index(trimmed.startIndex, offsetBy: 4)
            let end = trimmed.range(of: "</js>")?.lowerBound ?? trimmed.endIndex
            script = String(trimmed[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
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
            let resultText = evaluated.trimmingCharacters(in: .whitespacesAndNewlines)
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
