import Foundation

/// Result of normalizing an Android Legado JavaScript fragment for the
/// synchronous JavaScriptCore bridge used by SourceReadSwift.
///
/// The native network bridge is intentionally synchronous (JavaScriptCore
/// callbacks cannot safely block on Swift concurrency).  Android sources
/// commonly spell these same calls with `await`, `async` and Promise chains.
/// This normalizer removes only those execution keywords outside strings,
/// comments and regular-expression literals; the existing synchronous host
/// shims then execute the call immediately.
struct LegadoJavaScriptNormalization: Equatable, Hashable, Sendable {
    let originalScript: String
    let normalizedScript: String
    let features: [String]

    var changed: Bool { originalScript != normalizedScript }
}

enum LegadoJavaScriptCompatibility {
    static func normalize(_ script: String) -> LegadoJavaScriptNormalization {
        let unwrapped = unwrap(script)
        var features = Set<String>()
        let lexicalFeatures = detectFeatures(in: unwrapped)
        features.formUnion(lexicalFeatures)

        let normalized = stripExecutionKeywords(from: unwrapped, features: &features)
        if normalized != unwrapped { features.insert("sync-normalization") }
        return LegadoJavaScriptNormalization(
            originalScript: unwrapped,
            normalizedScript: normalized,
            features: features.sorted()
        )
    }

    /// Normalizes a source-level `jsLib` bundle.
    ///
    /// jsLib code is written against Rhino's Java objects, where a
    /// `StringBuilder(...).toString()` result answers `length()` as a method.
    /// Rule scripts, in contrast, are written against Legado's JavaScript
    /// strings where `length` is a number, and host shims such as
    /// `java.getFile(...).length()` expose real methods that must not be
    /// rewritten.  Only jsLib bundles get the `.length()` rewrite.
    static func normalizeJavaScriptLibrary(_ script: String) -> String {
        var features = Set<String>()
        let normalized = normalize(script).normalizedScript
        return rewriteJavaStringLengthCalls(in: normalized, features: &features)
    }

    /// Normalizes a book-source rule script (`@js:` / `<js>` / search-URL JS).
    ///
    /// Android sources are written against Rhino, where a String returned by
    /// `java.ajax` answers `length()` as a method, so rules contain calls such
    /// as `rev.length()`.  JavaScriptCore throws "rev.length is not a
    /// function".  Rewrite the empty-argument call form only; property reads
    /// (`s.length`), argument lists (`list.length(3)`) and the host File
    /// facade (`file.length()`, which is a real Java method) stay untouched.
    static func normalizeRuleScript(_ script: String) -> String {
        var features = Set<String>()
        let normalized = normalize(script).normalizedScript
        return rewriteJavaStringLengthCalls(
            in: normalized,
            features: &features,
            skipHostFileReceivers: true
        )
    }

    private static func unwrap(_ script: String) -> String {
        var value = script.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@js:") {
            value = String(value.dropFirst(4))
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("<js>"), value.hasSuffix("</js>") {
            value = String(value.dropFirst(4).dropLast(5))
        }
        return value
    }

    private static func detectFeatures(in source: String) -> Set<String> {
        var features = Set<String>()
        let visible = lexicalVisibleText(source)
        let lower = visible.lowercased()
        if containsToken(lower, "await") { features.insert("await") }
        if containsToken(lower, "async") { features.insert("async") }
        if containsToken(lower, "promise") { features.insert("promise") }
        if containsToken(lower, "globalthis") { features.insert("globalThis") }
        if containsToken(lower, "urlsearchparams") { features.insert("URLSearchParams") }
        if containsToken(lower, "queuemicrotask") { features.insert("queueMicrotask") }
        if containsToken(lower, "settimeout") { features.insert("setTimeout") }
        for name in ["ajax", "ajaxall", "post", "fetch", "connect", "importscript", "postform", "ajax_bytes", "base64encode", "base64decode", "md5encode", "timeformat", "getstringlist"] {
            if lower.range(of: "java.\(name)") != nil { features.insert("java.\(name)") }
        }
        return features
    }

    private static func containsToken(_ source: String, _ token: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_$])\(NSRegularExpression.escapedPattern(for: token))(?![A-Za-z0-9_$])") else { return false }
        return regex.firstMatch(in: source, range: NSRange(source.startIndex..<source.endIndex, in: source)) != nil
    }

    /// Replaces strings/comments/regexes with whitespace so feature detection
    /// and keyword stripping can never alter literal data.
    private static func lexicalVisibleText(_ source: String) -> String {
        var output = Array(repeating: Character(" "), count: source.count)
        let chars = Array(source)
        var index = 0
        var state = 0 // 0 normal, 1 single, 2 double, 3 template, 4 line, 5 block, 6 regex
        var escaped = false
        var inClass = false
        var previousSignificant: Character?
        while index < chars.count {
            let c = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            switch state {
            case 0:
                if c == "'" { state = 1; output[index] = " " }
                else if c == "\"" { state = 2; output[index] = " " }
                else if c == "`" { state = 3; output[index] = " " }
                else if c == "/", next == "/" { state = 4; output[index] = " "; index += 1; output[index] = " " }
                else if c == "/", next == "*" { state = 5; output[index] = " "; index += 1; output[index] = " " }
                else if c == "/", isRegexStart(previousSignificant) { state = 6; output[index] = " " }
                else { output[index] = c; if !c.isWhitespace { previousSignificant = c } }
            case 1, 2, 3:
                output[index] = c.isNewline ? c : " "
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if (state == 1 && c == "'") || (state == 2 && c == "\"") || (state == 3 && c == "`") { state = 0 }
            case 4:
                output[index] = c.isNewline ? c : " "
                if c.isNewline { state = 0; previousSignificant = c }
            case 5:
                output[index] = c.isNewline ? c : " "
                if c == "*", next == "/" { index += 1; output[index] = " "; state = 0 }
            case 6:
                output[index] = c.isNewline ? c : " "
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "[" { inClass = true }
                else if c == "]" { inClass = false }
                else if c == "/", !inClass { state = 0; previousSignificant = c }
            default: break
            }
            index += 1
        }
        return String(output)
    }

    private static func stripExecutionKeywords(
        from source: String,
        features: inout Set<String>
    ) -> String {
        let chars = Array(source)
        var output = chars
        var index = 0
        var state = 0 // same lexical states as lexicalVisibleText
        var escaped = false
        var inClass = false
        var previousSignificant: Character?
        while index < chars.count {
            let c = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            switch state {
            case 0:
                if c == "'" { state = 1 }
                else if c == "\"" { state = 2 }
                else if c == "`" { state = 3 }
                else if c == "/", next == "/" { state = 4; index += 1 }
                else if c == "/", next == "*" { state = 5; index += 1 }
                else if c == "/", isRegexStart(previousSignificant) { state = 6 }
                else if isIdentifierStart(c) {
                    let start = index
                    var end = index + 1
                    while end < chars.count, isIdentifierPart(chars[end]) { end += 1 }
                    let word = String(chars[start..<end])
                    if word == "await" {
                        features.insert("await")
                        for position in start..<end { output[position] = " " }
                    } else if word == "async", shouldStripAsync(in: chars, end: end) {
                        features.insert("async")
                        for position in start..<end { output[position] = " " }
                    } else if word == "let" {
                        features.insert("let-to-var")
                        output[start] = "v"
                        output[start + 1] = "a"
                        output[start + 2] = "r"
                    } else if word == "const" {
                        features.insert("const-to-var")
                        output[start] = "v"
                        output[start + 1] = "a"
                        output[start + 2] = "r"
                        output[start + 3] = " "
                        output[start + 4] = " "
                    }
                    if !word.isEmpty { previousSignificant = word.last }
                    index = end - 1
                } else if !c.isWhitespace { previousSignificant = c }
            case 1, 2, 3:
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if (state == 1 && c == "'") || (state == 2 && c == "\"") || (state == 3 && c == "`") { state = 0 }
            case 4:
                if c.isNewline { state = 0; previousSignificant = c }
            case 5:
                if c == "*", next == "/" { index += 1; state = 0 }
            case 6:
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "[" { inClass = true }
                else if c == "]" { inClass = false }
                else if c == "/", !inClass { state = 0; previousSignificant = c }
            default: break
            }
            index += 1
        }
        return String(output)
    }

    /// Rewrites the Java-style empty-argument call `value.length()` into the
    /// JavaScript property read `value.length`.
    ///
    /// Legado runs Rhino, where `java.ajax()` and `java.getString()` return
    /// `java.lang.String` instances whose length is the method `length()`.
    /// Rule authors therefore write `rev.length()`, which throws
    /// "rev.length is not a function" on JavaScriptCore.  Only executable
    /// regions are touched: string literals, template literals, comments and
    /// regular-expression literals stay byte-for-byte identical.
    private static func rewriteJavaStringLengthCalls(
        in source: String,
        features: inout Set<String>,
        skipHostFileReceivers: Bool = false
    ) -> String {
        let chars = Array(source)
        guard chars.count > 8 else { return source }
        var output = chars
        var index = 0
        var state = 0 // same lexical states as lexicalVisibleText
        var escaped = false
        var inClass = false
        var previousSignificant: Character?
        while index < chars.count {
            let c = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            switch state {
            case 0:
                if c == "'" { state = 1 }
                else if c == "\"" { state = 2 }
                else if c == "`" { state = 3 }
                else if c == "/", next == "/" { state = 4; index += 1 }
                else if c == "/", next == "*" { state = 5; index += 1 }
                else if c == "/", isRegexStart(previousSignificant) { state = 6 }
                else if c == ".",
                        let close = javaLengthCallClose(in: chars, dot: index),
                        !(skipHostFileReceivers && hasHostFileReceiver(chars, dot: index)) {
                    for position in index...close { output[position] = " " }
                    output[index] = "."
                    let letters = Array("length")
                    for offset in 0..<letters.count { output[index + 1 + offset] = letters[offset] }
                    features.insert("java-string-length")
                    previousSignificant = "h"
                    index = close
                } else if !c.isWhitespace {
                    previousSignificant = c
                }
            case 1, 2, 3:
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if (state == 1 && c == "'") || (state == 2 && c == "\"") || (state == 3 && c == "`") { state = 0 }
            case 4:
                if c.isNewline { state = 0; previousSignificant = c }
            case 5:
                if c == "*", next == "/" { index += 1; state = 0 }
            case 6:
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "[" { inClass = true }
                else if c == "]" { inClass = false }
                else if c == "/", !inClass { state = 0; previousSignificant = c }
            default: break
            }
            index += 1
        }
        return String(output)
    }

    /// True when the member access ending at `dot` is a host File facade
    /// (`file.length()`, `java.getFile(path).length()`) whose `length` is a
    /// real method and must not be rewritten into a property read.
    private static func hasHostFileReceiver(_ chars: [Character], dot: Int) -> Bool {
        var start = dot
        var steps = 0
        while start > 0, steps < 64 {
            start -= 1
            steps += 1
            let ch = chars[start]
            if ch == ";" || ch == "{" || ch == "}" || ch.isNewline { break }
        }
        let window = String(chars[start..<dot])
        if window.contains("getFile") { return true }
        // `file.length()`: the receiver is the bare identifier `file`
        // (or `this.file`).  Match the last identifier token before the dot.
        let trimmed = window.trimmingCharacters(in: .whitespaces)
        let tail = trimmed.reversed().prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return String(tail.reversed()) == "file"
    }

    /// Returns the index of `)` when `chars[dot...]` starts the empty-argument
    /// call `.length()`, ignoring whitespace.  Any argument list is rejected.
    private static func javaLengthCallClose(in chars: [Character], dot: Int) -> Int? {
        var cursor = dot + 1
        while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
        let name = Array("length")
        guard cursor + name.count <= chars.count else { return nil }
        guard Array(chars[cursor..<(cursor + name.count)]) == name else { return nil }
        cursor += name.count
        guard cursor >= chars.count || !isIdentifierPart(chars[cursor]) else { return nil }
        while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
        guard cursor < chars.count, chars[cursor] == "(" else { return nil }
        cursor += 1
        while cursor < chars.count, chars[cursor].isWhitespace { cursor += 1 }
        guard cursor < chars.count, chars[cursor] == ")" else { return nil }
        return cursor
    }

    private static func shouldStripAsync(in chars: [Character], end: Int) -> Bool {
        var position = end
        while position < chars.count, chars[position].isWhitespace { position += 1 }
        guard position < chars.count else { return false }
        if chars[position...].starts(with: Array("function")) {
            let endOfFunction = position + "function".count
            return endOfFunction == chars.count || !isIdentifierPart(chars[endOfFunction])
        }
        if chars[position] == "(" {
            var depth = 1
            position += 1
            while position < chars.count, depth > 0 {
                if chars[position] == "(" { depth += 1 }
                else if chars[position] == ")" { depth -= 1 }
                position += 1
            }
            while position < chars.count, chars[position].isWhitespace { position += 1 }
            return position + 1 < chars.count && chars[position] == "=" && chars[position + 1] == ">"
        }
        let start = position
        while position < chars.count, isIdentifierPart(chars[position]) { position += 1 }
        guard position > start else { return false }
        while position < chars.count, chars[position].isWhitespace { position += 1 }
        return position + 1 < chars.count && chars[position] == "=" && chars[position + 1] == ">"
    }

    private static func isRegexStart(_ previous: Character?) -> Bool {
        guard let previous else { return true }
        return "=([{,:;!&|?+-*%^~<>".contains(previous)
    }

    private static func isIdentifierStart(_ value: Character) -> Bool {
        value == "_" || value == "$" || value.isLetter
    }

    private static func isIdentifierPart(_ value: Character) -> Bool {
        isIdentifierStart(value) || value.isNumber
    }
}
