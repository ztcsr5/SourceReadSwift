import Foundation
import JavaScriptCore

/// Validates a purification rule without running its JavaScript or modifying text.
enum PurifyRuleValidator {
    static func error(in rule: String) -> String? {
        let clean = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "请输入正则或替换规则" }
        if clean.hasPrefix("@js:") || clean.hasPrefix("<js>") {
            let script: String
            if clean.hasPrefix("<js>") {
                guard clean.hasSuffix("</js>") else { return "JS 规则缺少 </js> 结束标记" }
                script = String(clean.dropFirst(4).dropLast(5))
            } else {
                script = String(clean.dropFirst(4))
            }
            guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "JS 规则不能为空" }
            guard let context = JSContext() else { return "无法校验 JS 规则，请重试" }
            guard let encoded = try? JSONEncoder().encode(script) else { return "无法编码 JS 规则" }
            // Pass source as a string argument; interpolating it into a function
            // expression would let a closing brace escape the validation wrapper.
            _ = context.evaluateScript("new Function(\(String(decoding: encoded, as: UTF8.self)))")
            return context.exception == nil ? nil : "JS 语法错误，请检查括号、引号和结束标记"
        }
        for line in clean.components(separatedBy: .newlines) where !line.isEmpty {
            let parts = line.components(separatedBy: "##")
            let pattern = line.hasPrefix("##") ? (parts.count > 1 ? parts[1] : "") : parts[0]
            guard !pattern.isEmpty else { return "替换规则的正则部分不能为空" }
            do {
                _ = try NSRegularExpression(pattern: pattern)
            } catch {
                return "正则语法错误，请检查括号、转义符和字符组"
            }
        }
        return nil
    }
}
