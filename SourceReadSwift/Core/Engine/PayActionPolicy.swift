import Foundation

/// Result of executing a Legado `ruleContent.payAction`（购买操作）.
///
/// Mirrors `ReadBookActivity.payAction()`: an absolute URL opens the purchase
/// page, a truthy result means the chapter list should reload, and everything
/// else is a failure reported back to the reader.
enum PayActionOutcome: Equatable, Sendable {
    case openURL(URL)
    case purchased
    case failed(String)
}

/// Pure evaluation policy for `ruleContent.payAction`.
///
/// Legado documents the field as “购买操作, js 或者包含 {{js}} 的 url” and runs it
/// through `AnalyzeRule.evalJS`. The returned string is classified as:
/// - `http(s)://…` → open the purchase page;
/// - any non-false value (`true`, `1`, `ok`, `success`, …) → purchase succeeded;
/// - `false` / `no` / `not` / `0` / blank → no visible effect.
///
/// Keeping the template scan and classification pure makes the behaviour
/// testable without JavaScriptCore or a network stack.
enum PayActionPolicy {
    enum Segment: Equatable {
        case literal(String)
        case script(String)
    }

    /// Splits a template into literal text and `{{…}}` script segments.
    ///
    /// An unterminated `{{` is kept as literal text so a malformed rule fails
    /// closed instead of silently dropping the rest of a purchase URL.
    static func segments(in rule: String) -> [Segment] {
        var result: [Segment] = []
        var cursor = rule.startIndex
        var literalStart = cursor
        while cursor < rule.endIndex,
              let open = rule[cursor...].range(of: "{{") {
            guard let close = rule[open.upperBound...].range(of: "}}") else { break }
            if open.lowerBound > literalStart {
                result.append(.literal(String(rule[literalStart..<open.lowerBound])))
            }
            result.append(.script(String(rule[open.upperBound..<close.lowerBound])))
            cursor = close.upperBound
            literalStart = cursor
        }
        if literalStart < rule.endIndex {
            result.append(.literal(String(rule[literalStart..<rule.endIndex])))
        }
        return result
    }

    /// Evaluates the rule and classifies its string result.
    ///
    /// A rule containing `{{…}}` is a URL/string template: every script segment
    /// is evaluated and spliced into the surrounding literal text. A rule
    /// without template markers is executed as one JS snippet, matching
    /// Legado's `evalJS(payAction)` call.
    static func evaluate(
        rule: String,
        evaluateJS: (String) -> Result<String, SourceEngineError>
    ) -> Result<PayActionOutcome, SourceEngineError> {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.rule("购买操作规则为空")) }

        let parts = segments(in: trimmed)
        let hasScript = parts.contains {
            if case .script = $0 { return true }
            return false
        }

        // A raw absolute URL has no JS to resolve. Feeding `https://…` to
        // JavaScriptCore as a statement is a syntax error, so short-circuit it.
        // Template rules still take the evaluator path below and are classified
        // after their `{{…}}` segments have been expanded.
        if !hasScript, let outcome = absoluteURLOutcome(from: trimmed) {
            return .success(outcome)
        }

        let raw: String
        if hasScript {
            var output = ""
            for part in parts {
                switch part {
                case .literal(let text):
                    output += text
                case .script(let script):
                    switch evaluateJS(script) {
                    case .success(let value):
                        output += value
                    case .failure(let error):
                        return .failure(error)
                    }
                }
            }
            raw = output
        } else {
            switch evaluateJS(trimmed) {
            case .success(let value):
                raw = value
            case .failure(let error):
                return .failure(error)
            }
        }
        return .success(classify(raw))
    }

    static func classify(_ raw: String) -> PayActionOutcome {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let outcome = absoluteURLOutcome(from: value) {
            return outcome
        }
        if isTruthy(value) {
            return .purchased
        }
        return .failed(value.isEmpty ? "购买操作未返回结果" : "购买操作未生效：\(value)")
    }

    /// Legado's `isAbsUrl()`: only explicit `http://` / `https://` values are
    /// opened; relative paths must be resolved by the source rule itself.
    static func absoluteURL(from value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        return URL(string: trimmed)
    }

    /// `nil` means “not an absolute URL”; a malformed `http(s)` value returns
    /// `.failed` instead of falling through to `isTruthy`, where Legado's
    /// permissive truthiness would report a bogus purchase.
    static func absoluteURLOutcome(from value: String) -> PayActionOutcome? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        guard let url = URL(string: trimmed) else {
            return .failed("购买操作 URL 无效：\(trimmed)")
        }
        return .openURL(url)
    }

    /// Legado `String?.isTrue(nullIsTrue = false)`: blank / literal `null` are
    /// false; `false` / `no` / `not` / `0` are false; every other non-empty
    /// value is true. Sources commonly return `"ok"` or `"success"`, so a
    /// strict true/1 allow-list would silently drop valid purchases.
    static func isTruthy(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty || normalized == "null" { return false }
        return !["false", "no", "not", "0"].contains(normalized)
    }
}
