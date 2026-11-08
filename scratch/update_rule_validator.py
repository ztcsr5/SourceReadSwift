path = r"D:\Gemini反重力\SourceReadSwift2\SourceReadSwift\Core\Rules\RuleEditorValidator.swift"
with open(path, "r", encoding="utf-8") as f:
    text = f.read().replace("\r\n", "\n")

target = """    private func javaScriptBody(_ rule: String) -> String? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@js:") {
            return String(trimmed.dropFirst(4))
        }
        if trimmed.hasPrefix("<js>"), trimmed.hasSuffix("</js>") {
            return String(trimmed.dropFirst(4).dropLast(5))
        }
        return nil
    }"""

replacement = """    private func javaScriptBody(_ rule: String) -> String? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("@js:") {
            return String(trimmed.dropFirst(4))
        }
        if trimmed.hasPrefix("<js>"), trimmed.hasSuffix("</js>") {
            return String(trimmed.dropFirst(4).dropLast(5))
        }
        if let start = trimmed.range(of: "<js>"),
           let end = trimmed.range(of: "</js>", range: start.upperBound..<trimmed.endIndex) {
            return String(trimmed[start.upperBound..<end.lowerBound])
        }
        return nil
    }"""

assert target in text, "target not found in RuleEditorValidator.swift"
updated = text.replace(target, replacement)
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(updated)
print("SUCCESS: RuleEditorValidator.swift updated!")
