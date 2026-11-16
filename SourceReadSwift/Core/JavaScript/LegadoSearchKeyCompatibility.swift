import Foundation

/// Adapts Rhino's host `key` binding only for an unambiguous search-URL declaration.
enum LegadoSearchKeyCompatibility {
    private struct Token {
        let spelling: String
        let range: Range<Int>
        let hasLineBreakBefore: Bool
    }

    /// Keeps unfamiliar syntax unchanged so JavaScriptCore still reports its original errors.
    static func normalize(_ script: String, hasHostKey: Bool) -> String {
        guard hasHostKey, !script.contains("`"), !script.contains("use strict") else { return script }
        let characters = Array(script)
        let tokens = tokenize(LegadoJavaScriptCompatibility.lexicalVisibleText(script, maskRegularExpressions: false))
        // These forms introduce scopes or hidden declarations that this narrow scanner does not resolve.
        let unsupported: Set<String> = ["function", "class", "catch", "eval", "with", "import", "export", "return", "\\", "/"]
        guard !tokens.contains(where: { unsupported.contains($0.spelling) }) else { return script }
        guard !tokens.indices.dropFirst().contains(where: {
            tokens[$0 - 1].spelling == "=" && tokens[$0].spelling == ">"
        }) else { return script }
        var delimiters: [String] = []
        var candidate: Range<Int>?
        for index in tokens.indices {
            let word = tokens[index].spelling
            if ["var", "let", "const"].contains(word), index == 0 || tokens[index - 1].spelling != "." {
                guard delimiters.isEmpty,
                      index == 0 || tokens[index - 1].spelling == ";" || tokens[index].hasLineBreakBefore,
                      index + 3 < tokens.count, isIdentifier(tokens[index + 1].spelling),
                      tokens[index + 2].spelling == "=",
                      let end = initializerEnd(tokens, from: index + 3) else { return script }
                if tokens[index + 1].spelling == "key" {
                    guard candidate == nil, word == "let", referencesKey(tokens, in: (index + 3)..<end) else { return script }
                    let endOffset = tokens[end - 1].range.upperBound
                    guard !characters[tokens[index].range.lowerBound..<endOffset].contains(where: \.isNewline),
                          !tokens[(index + 3)..<end].contains(where: { $0.spelling == "{" }) else { return script }
                    candidate = tokens[index].range
                }
            }
            guard updateDelimiters(word, stack: &delimiters) else { return script }
        }
        guard delimiters.isEmpty, let candidate else { return script }
        var adapted = characters
        // Rhino 1.8.1 reads and writes the prebound host property for this declaration.
        adapted.replaceSubrange(candidate, with: "var")
        return String(adapted)
    }

    private static func tokenize(_ visible: String) -> [Token] {
        let characters = Array(visible)
        var tokens: [Token] = []
        var cursor = 0
        var hasLineBreak = false
        while cursor < characters.count {
            if characters[cursor].isWhitespace {
                hasLineBreak = hasLineBreak || characters[cursor].isNewline
                cursor += 1
                continue
            }
            let start = cursor
            cursor += 1
            if isIdentifierStart(characters[start]) {
                while cursor < characters.count,
                      isIdentifierStart(characters[cursor]) || characters[cursor].isNumber { cursor += 1 }
            }
            tokens.append(Token(spelling: String(characters[start..<cursor]), range: start..<cursor,
                                hasLineBreakBefore: hasLineBreak))
            hasLineBreak = false
        }
        return tokens
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$"
    }

    private static func isIdentifier(_ spelling: String) -> Bool {
        spelling.first.map(isIdentifierStart) ?? false
    }

    private static func initializerEnd(_ tokens: [Token], from start: Int) -> Int? {
        var delimiters: [String] = []
        for index in start..<tokens.count {
            let word = tokens[index].spelling
            if delimiters.isEmpty, word == ";" { return index }
            if delimiters.isEmpty, ["let", "const", "var"].contains(word),
               index == 0 || tokens[index - 1].spelling != "." {
                // A new declaration after a line break cannot continue the prior initializer.
                return tokens[index].hasLineBreakBefore ? index : nil
            }
            // Multiple bindings need a full parser; do not guess their declaration scope.
            if delimiters.isEmpty, word == "," { return nil }
            guard updateDelimiters(word, stack: &delimiters) else { return nil }
        }
        return delimiters.isEmpty ? tokens.count : nil
    }

    private static func referencesKey(_ tokens: [Token], in range: Range<Int>) -> Bool {
        range.contains { index in
            tokens[index].spelling == "key"
                && (index == range.lowerBound || tokens[index - 1].spelling != ".")
                && (index + 1 == range.upperBound || tokens[index + 1].spelling != ":")
        }
    }

    private static func updateDelimiters(_ word: String, stack: inout [String]) -> Bool {
        if ["(", "[", "{"].contains(word) { stack.append(word) }
        if let expected = [")": "(", "]": "[", "}": "{"][word] {
            guard stack.last == expected else { return false }
            stack.removeLast()
        }
        return true
    }
}
