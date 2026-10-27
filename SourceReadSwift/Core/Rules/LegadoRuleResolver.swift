import Foundation
import CoreFoundation

struct LegadoRuleResolver {
    /// Percent-encodes a search keyword exactly the way Legado feeds `{{key}}`.
    ///
    /// `.urlQueryAllowed` keeps `& = + ? / :` literal, so a keyword such as
    /// `剑来&x` silently truncated the query string and the source answered
    /// with an empty page -- one of the "搜索解析结果为空" shapes in the
    /// 991-source diagnostic. Java's `URLEncoder.encode` percent-encodes every
    /// byte outside `A-Z a-z 0-9 . - _ *` and maps the space byte to `+`;
    /// Legado uses that string verbatim, so mirror it here.
    static func percentEncode(_ text: String, charset: String? = nil) -> String {
        let normalized = charset?.lowercased().replacingOccurrences(of: "-", with: "") ?? "utf8"
        let data: Data?
        if normalized == "gbk" || normalized == "gb2312" || normalized == "gb18030" {
            let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            data = text.data(using: String.Encoding(rawValue: nsEncoding))
        } else {
            data = text.data(using: .utf8)
        }
        guard let bytes = data else { return text }
        var output = ""
        output.reserveCapacity(bytes.count * 3)
        for byte in bytes {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x5F, 0x2E, 0x2A:
                output.append(Character(UnicodeScalar(byte)))
            case 0x20:
                output.append("+")
            default:
                output.append(String(format: "%%%02X", byte))
            }
        }
        return output
    }

    /// `charset: "escape"` selects Legado's `EncoderUtils.escape` instead of
    /// `java.net.URLEncoder` (AnalyzeUrl.kt L226-236).
    static func encodeKeyword(_ keyword: String, charset: String? = nil) -> String {
        if charset?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "escape" {
            return escapeEncode(keyword)
        }
        return percentEncode(keyword, charset: charset)
    }

    /// Android Legado `EncoderUtils.escape` (see app/src/main/java/io/legado/app/utils/EncoderUtils.kt L12-29).
    ///
    /// Only ASCII letters and digits survive; everything else becomes `%XX`
    /// (or `%uXXXX` above U+00FF).  This is deliberately stricter than the
    /// browser `escape()` builtin, which also keeps `- _ . * @ + /`.
    static func escapeEncode(_ value: String) -> String {
        var output = ""
        output.reserveCapacity(value.count * 3)
        for unit in value.utf16 {
            switch unit {
            case 0x30...0x39, 0x41...0x5A, 0x61...0x7A:
                if let scalar = Unicode.Scalar(unit) {
                    output.unicodeScalars.append(scalar)
                }
            case 0x0000...0x000F:
                output += "%0" + String(unit, radix: 16)
            case 0x0010...0x00FF:
                output += "%" + String(unit, radix: 16)
            default:
                output += "%u" + String(unit, radix: 16)
            }
        }
        return output
    }

    func interpolate(_ text: String, keyword: String? = nil, page: Int? = nil, baseUrl: String? = nil, charset: String? = nil) -> String {
        var output = text
        if let page {
            output = Self.replacePageAngles(in: output, page: page)
            output = replaceArithmeticExpressions(in: output, page: page)
            output = output.replacingOccurrences(of: "{{page}}", with: String(page))
            output = output.replacingOccurrences(of: "{page}", with: String(page))
        }
        if let keyword {
            let encoded = Self.encodeKeyword(keyword, charset: charset)
            output = output.replacingOccurrences(of: "{{key}}", with: encoded)
            output = output.replacingOccurrences(of: "{{keyword}}", with: encoded)
            output = output.replacingOccurrences(of: "{{searchKey}}", with: encoded)
            output = output.replacingOccurrences(of: "{key}", with: encoded)
            output = output.replacingOccurrences(of: "{keyword}", with: encoded)
            output = output.replacingOccurrences(of: "{searchKey}", with: encoded)
        }
        if let baseUrl {
            output = Self.replaceBaseUrlPlaceholders(in: output, baseUrl: baseUrl)
        }
        return output
    }

    static func replacePageAngles(in template: String, page: Int) -> String {
        guard template.contains("<"), template.contains(">"), template.contains(",") else {
            return template
        }
        guard let angleRegex = try? NSRegularExpression(pattern: #"<([^<>]+)>"#) else {
            return template
        }
        let nsTemplate = template as NSString
        let fullRange = NSRange(location: 0, length: nsTemplate.length)
        let jsRanges: [NSRange]
        if let jsRegex = try? NSRegularExpression(pattern: #"(?i)<js>[\s\S]*?</js>"#) {
            jsRanges = jsRegex.matches(in: template, range: fullRange).map(\.range)
        } else {
            jsRanges = []
        }

        let matches = angleRegex.matches(in: template, range: fullRange)
        guard !matches.isEmpty else { return template }

        var output = template
        for match in matches.reversed() {
            let matchRange = match.range(at: 0)
            if jsRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) {
                continue
            }
            guard match.numberOfRanges > 1,
                  let innerRange = Range(match.range(at: 1), in: output),
                  let outerRange = Range(matchRange, in: output) else {
                continue
            }
            let inner = String(output[innerRange])
            let lowerInner = inner.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lowerInner == "js" || lowerInner == "/js" || !inner.contains(",") {
                continue
            }
            let choices = inner.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard !choices.isEmpty else { continue }
            let targetIndex = page <= 1 ? 0 : min(page - 1, choices.count - 1)
            let chosen = choices.indices.contains(targetIndex) ? choices[targetIndex] : (choices.last ?? "")
            output.replaceSubrange(outerRange, with: chosen)
        }
        return output
    }

    static func replaceBaseUrlPlaceholders(in text: String, baseUrl: String) -> String {
        let cleanBase = baseUrl
            .components(separatedBy: "#")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanBase.isEmpty else { return text }

        let placeholders = [
            "{{source.bookSourceUrl}}",
            "{source.bookSourceUrl}",
            "{{source.cleanSourceUrl}}",
            "{source.cleanSourceUrl}",
            "{{source.sourceUrl}}",
            "{source.sourceUrl}",
            "{{source.baseUrl}}",
            "{source.baseUrl}",
            "{{bookSourceUrl}}",
            "{bookSourceUrl}",
            "{{cleanSourceUrl}}",
            "{cleanSourceUrl}",
            "{{sourceUrl}}",
            "{sourceUrl}",
            "{{baseUrl}}",
            "{baseUrl}"
        ]
        var output = text
        for placeholder in placeholders {
            output = replaceSingleBasePlaceholder(in: output, placeholder: placeholder, cleanBase: cleanBase)
        }
        return output
    }

    private static func replaceSingleBasePlaceholder(in text: String, placeholder: String, cleanBase: String) -> String {
        guard text.contains(placeholder) else { return text }
        let baseNoSlash = cleanBase.hasSuffix("/") ? String(cleanBase.dropLast()) : cleanBase
        var output = text
        var searchStart = output.startIndex
        while searchStart < output.endIndex,
              let range = output.range(of: placeholder, range: searchStart..<output.endIndex) {
            let nextChar: Character? = range.upperBound < output.endIndex ? output[range.upperBound] : nil
            let replacement: String
            if nextChar == "/" {
                replacement = baseNoSlash
            } else if let nextChar, !["/", "?", "#", ",", "@", "&"].contains(nextChar) {
                replacement = baseNoSlash + "/"
            } else {
                replacement = cleanBase
            }
            output.replaceSubrange(range, with: replacement)
            searchStart = output.index(range.lowerBound, offsetBy: replacement.count, limitedBy: output.endIndex) ?? output.endIndex
        }
        return output
    }

    func splitLegadoRule(_ rule: String) -> [String] {
        rule
            .components(separatedBy: "&&")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func isJavaScriptRule(_ rule: String) -> Bool {
        var trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("+") || trimmed.hasPrefix("-") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed.hasPrefix("@js:") || trimmed.hasPrefix("<js>") || trimmed.hasPrefix("java.")
    }

    private func replaceArithmeticExpressions(in text: String, page: Int) -> String {
        let pattern = "\\{\\{\\s*([^{}]+)\\s*\\}\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var output = text
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let expression = nsText.substring(with: match.range(at: 1))
            guard let value = evaluatePageArithmetic(expression, page: page) else { continue }
            output = (output as NSString).replacingCharacters(in: match.range(at: 0), with: String(value))
        }
        return output
    }

    private func evaluatePageArithmetic(_ expression: String, page: Int) -> Int? {
        let replaced = expression
            .replacingOccurrences(of: "page", with: String(page))
            .replacingOccurrences(of: " ", with: "")
        guard !replaced.isEmpty,
              replaced.range(of: #"^[0-9+\-*/()]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        var parser = IntegerExpressionParser(replaced)
        return parser.parse()
    }
}

private struct IntegerExpressionParser {
    private let chars: [Character]
    private var index = 0

    init(_ text: String) {
        self.chars = Array(text)
    }

    mutating func parse() -> Int? {
        guard let value = parseExpression(), index == chars.count else { return nil }
        return value
    }

    private mutating func parseExpression() -> Int? {
        guard var value = parseTerm() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            advance()
            guard let rhs = parseTerm() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private mutating func parseTerm() -> Int? {
        guard var value = parseFactor() else { return nil }
        while let op = peek(), op == "*" || op == "/" {
            advance()
            guard let rhs = parseFactor() else { return nil }
            if op == "/" {
                guard rhs != 0 else { return nil }
                value /= rhs
            } else {
                value *= rhs
            }
        }
        return value
    }

    private mutating func parseFactor() -> Int? {
        guard let current = peek() else { return nil }
        if current == "(" {
            advance()
            guard let value = parseExpression(), peek() == ")" else { return nil }
            advance()
            return value
        }
        return parseNumber()
    }

    private mutating func parseNumber() -> Int? {
        let start = index
        while let current = peek(), current.isNumber {
            advance()
        }
        guard index > start else { return nil }
        return Int(String(chars[start..<index]))
    }

    private func peek() -> Character? {
        index < chars.count ? chars[index] : nil
    }

    private mutating func advance() {
        index += 1
    }
}
