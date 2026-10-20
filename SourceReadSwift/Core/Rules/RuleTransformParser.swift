import Foundation

/// A single Legado `##` regex transform.
///
/// Legado splits a rule on `##` exactly once per rule and reads at most three
/// trailing fields (see `AnalyzeRuleCore`):
///   `path##pattern##replacement##replaceFirstFlag`
/// - `pattern` empty means "no transform".
/// - `replacement` defaults to the empty string.
/// - any fourth field (even empty) switches on `replaceFirst`; later fields are ignored.
struct RuleRegexTransform: Equatable {
    let pattern: String
    let replacement: String
    let replaceFirst: Bool
}

/// Shared parser/executor for Legado `##` transforms.
///
/// Both the HTML and JSON extractors use this type so the two pipelines cannot
/// drift apart again.
enum RuleTransformParser {
    /// Splits `path##pattern##replacement##flag` using Legado's semantics.
    /// The returned path is trimmed, matching `ruleStrS[0].trim()` upstream.
    static func split(_ rawRule: String) -> (path: String, transform: RuleRegexTransform?) {
        let parts = rawRule.components(separatedBy: "##")
        let path = (parts.first ?? rawRule).trimmingCharacters(in: .whitespacesAndNewlines)
        guard parts.count > 1 else { return (path, nil) }
        return (path, transform(fromTrailingParts: parts.dropFirst()))
    }

    /// Builds a transform from the fields after the first `##`.
    static func transform(fromTrailingParts parts: ArraySlice<String>) -> RuleRegexTransform? {
        guard let first = parts.first else { return nil }
        guard !first.isEmpty else { return nil }
        let replacement = parts.count > 1 ? parts[parts.startIndex + 1] : ""
        return RuleRegexTransform(
            pattern: first,
            replacement: replacement,
            replaceFirst: parts.count > 2
        )
    }

    /// Applies the transform with Legado's exact fallback behaviour.
    static func apply(_ transform: RuleRegexTransform?, to value: String) -> String {
        guard let transform, !transform.pattern.isEmpty else { return value }
        guard let regex = try? NSRegularExpression(pattern: transform.pattern) else {
            // Legado: invalid pattern -> literal replace (or replacement for replaceFirst).
            return transform.replaceFirst
                ? transform.replacement
                : value.replacingOccurrences(of: transform.pattern, with: transform.replacement)
        }
        let fullRange = NSRange(location: 0, length: (value as NSString).length)
        if transform.replaceFirst {
            let source = value as NSString
            guard let match = regex.firstMatch(in: value, options: [], range: fullRange) else {
                // Legado returns an empty string when replaceFirst finds no match.
                return ""
            }
            let matched = source.substring(with: match.range)
            let matchedRange = NSRange(location: 0, length: (matched as NSString).length)
            guard let inner = regex.firstMatch(in: matched, options: [], range: matchedRange) else {
                return ""
            }
            let expanded = regex.replacementString(
                for: inner,
                in: matched,
                offset: 0,
                template: transform.replacement
            )
            return (matched as NSString).replacingCharacters(in: inner.range, with: expanded)
        }
        return regex.stringByReplacingMatches(
            in: value,
            options: [],
            range: fullRange,
            withTemplate: transform.replacement
        )
    }
}