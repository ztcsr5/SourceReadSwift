import Foundation

struct PurifyRuleEvaluator {
    static func apply(
        rule: String,
        to text: String,
        variables: [String: Any] = [:],
        executionContext: RuleExecutionContext? = nil
    ) -> String {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        if trimmed.hasPrefix("@js:") || (trimmed.hasPrefix("<js>") && trimmed.hasSuffix("</js>")) {
            var script = trimmed
            if script.hasPrefix("@js:") {
                script = String(script.dropFirst(4))
            } else if script.hasPrefix("<js>") && script.hasSuffix("</js>") {
                let start = script.index(script.startIndex, offsetBy: 4)
                let end = script.index(script.endIndex, offsetBy: -5)
                script = String(script[start..<end])
            }
            var jsVars = variables
            jsVars["result"] = text
            let runtime = JSCoreRuntime(executionContext: executionContext ?? RuleExecutionContext())
            let evaluated = runtime.evaluate(script, variables: jsVars)
            switch evaluated {
            case .success(let val):
                return val
            case .failure:
                if script.contains("return") {
                    if case .success(let val) = runtime.evaluate("(function(){\(script)})()", variables: jsVars) {
                        return val
                    }
                }
                return text
            }
        }

        let lines = rule
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return apply(rules: lines.isEmpty ? [rule] : lines, to: text, variables: variables, executionContext: executionContext)
    }

    static func apply(
        rules: [String],
        to text: String,
        variables: [String: Any] = [:],
        executionContext: RuleExecutionContext? = nil
    ) -> String {
        rules.reduce(text) { output, item in
            let clean = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return output }

            if clean.hasPrefix("@js:") || (clean.hasPrefix("<js>") && clean.hasSuffix("</js>")) {
                return apply(rule: clean, to: output, variables: variables, executionContext: executionContext)
            }

            if clean.contains("##") {
                let parts = clean.components(separatedBy: "##")
                return replaceRegex(
                    pattern: parts.first ?? "",
                    replacement: parts.dropFirst().first ?? "",
                    in: output
                )
            }
            return replaceRegex(pattern: clean, replacement: "", in: output)
        }
    }

    static func apply(rule: String, to text: String) -> String {
        apply(rule: rule, to: text, variables: [:], executionContext: nil)
    }

    static func apply(rules: [String], to text: String) -> String {
        apply(rules: rules, to: text, variables: [:], executionContext: nil)
    }

    private static func replaceRegex(pattern: String, replacement: String, in text: String) -> String {
        guard !pattern.isEmpty,
              let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }
}

