import Foundation

struct RuleOperatorSplitter {
    static func split(_ text: String, separator: String) -> [String]? {
        guard !separator.isEmpty else { return nil }
        let parts = splitAll(text, separator: separator)
        let filtered = parts.filter { !$0.isEmpty }
        return filtered.count > 1 ? filtered : nil
    }

    /// Returns the first top-level Legado rule operator in source order together
    /// with the text split on that operator. Mirrors RuleAnalyzer.splitRule:
    /// whichever of `&&`, `||`, `%%` appears first wins, and only top-level
    /// occurrences (outside quotes, escapes, `[]`, `()`, `{}`) are considered.
    static func firstOperator(
        in text: String,
        ignoringJavaScriptBlocks: Bool = false
    ) -> (op: String, parts: [String])? {
        var index = text.startIndex
        var quote: Character?
        var escaped = false
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while index < text.endIndex {
            if quote == nil, ignoringJavaScriptBlocks, text[index...].hasPrefix("<js>") {
                guard let end = text.range(of: "</js>", range: text.index(index, offsetBy: 4)..<text.endIndex) else {
                    return nil
                }
                index = end.upperBound
                continue
            }

            let char = text[index]
            if let activeQuote = quote {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == activeQuote {
                    quote = nil
                }
                index = text.index(after: index)
                continue
            }

            if char == "\"" || char == "'" {
                quote = char
                index = text.index(after: index)
                continue
            }

            switch char {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if parenDepth == 0, bracketDepth == 0, braceDepth == 0 {
                for op in ["&&", "||", "%%"] where text[index...].hasPrefix(op) {
                    return (op, splitAll(text, separator: op, ignoringJavaScriptBlocks: ignoringJavaScriptBlocks))
                }
            }

            index = text.index(after: index)
        }

        return nil
    }

    private static func splitAll(
        _ text: String,
        separator: String,
        ignoringJavaScriptBlocks: Bool = false
    ) -> [String] {
        var parts: [String] = []
        var buffer = ""
        var index = text.startIndex
        var quote: Character?
        var escaped = false
        var parenDepth = 0
        var bracketDepth = 0
        var braceDepth = 0

        while index < text.endIndex {
            if quote == nil, ignoringJavaScriptBlocks, text[index...].hasPrefix("<js>") {
                buffer.append("<js>")
                index = text.index(index, offsetBy: 4)
                guard let end = text.range(of: "</js>", range: index..<text.endIndex) else {
                    buffer.append(contentsOf: text[index...])
                    break
                }
                buffer.append(contentsOf: text[index..<end.upperBound])
                index = end.upperBound
                continue
            }

            let char = text[index]
            if let activeQuote = quote {
                buffer.append(char)
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == activeQuote {
                    quote = nil
                }
                index = text.index(after: index)
                continue
            }

            if char == "\"" || char == "'" {
                quote = char
                buffer.append(char)
                index = text.index(after: index)
                continue
            }
            switch char {
            case "(":
                parenDepth += 1
            case ")":
                parenDepth = max(0, parenDepth - 1)
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth = max(0, bracketDepth - 1)
            case "{":
                braceDepth += 1
            case "}":
                braceDepth = max(0, braceDepth - 1)
            default:
                break
            }

            if parenDepth == 0,
               bracketDepth == 0,
               braceDepth == 0,
               text[index...].hasPrefix(separator) {
                parts.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
                buffer.removeAll()
                index = text.index(index, offsetBy: separator.count)
                continue
            }

            buffer.append(char)
            index = text.index(after: index)
        }

        parts.append(buffer.trimmingCharacters(in: .whitespacesAndNewlines))
        return parts
    }
}
