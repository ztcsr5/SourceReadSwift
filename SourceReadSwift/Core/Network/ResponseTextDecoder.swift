import Foundation
import CoreFoundation

struct ResponseTextDecoder {
    func decode(data: Data, headers: [String: String], preferredCharset: String? = nil) -> String {
        // 1. Check Byte Order Mark (BOM)
        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            if let text = String(data: data.dropFirst(3), encoding: .utf8) {
                return text
            }
        } else if data.count >= 2 && data[0] == 0xFF && data[1] == 0xFE {
            if let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) {
                return text
            }
        } else if data.count >= 2 && data[0] == 0xFE && data[1] == 0xFF {
            if let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) {
                return text
            }
        }

        // 2. Preferred charset (from source rule or URL directive)
        if let preferredCharset,
           let text = decode(data: data, charset: preferredCharset) {
            return text
        }

        // 3. HTTP Header Content-Type charset
        if let charset = charset(from: headers),
           let text = decode(data: data, charset: charset) {
            return text
        }

        // 4. In-HTML meta charset sniffing
        if let charset = sniffCharset(from: data),
           let text = decode(data: data, charset: charset) {
            return text
        }

        // 5. Fallback cascade: UTF-8 -> GB18030 / GBK -> Big5 -> ISO-8859-1
        return String(data: data, encoding: .utf8)
            ?? decode(data: data, charset: "gb18030")
            ?? decode(data: data, charset: "gbk")
            ?? decode(data: data, charset: "big5")
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private func charset(from headers: [String: String]) -> String? {
        let contentType = headers.first { key, _ in
            key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value
        guard let contentType else { return nil }
        let parts = contentType.components(separatedBy: ";")
        for part in parts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("charset=") {
                return String(trimmed.dropFirst("charset=".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            }
        }
        return nil
    }

    private func sniffCharset(from data: Data) -> String? {
        let prefix = data.prefix(4096)
        let ascii = String(data: prefix, encoding: .ascii)
            ?? String(data: prefix, encoding: .isoLatin1)
            ?? ""
        let lower = ascii.lowercased()
        guard let range = lower.range(of: "charset") else { return nil }
        let tail = lower[range.upperBound...].prefix(80)
        guard let separator = tail.firstIndex(where: { $0 == "=" || $0 == ":" }) else { return nil }
        let value = tail[tail.index(after: separator)...]
            .drop(while: { $0 == "\"" || $0 == "'" || $0.isWhitespace })
            .prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        return value.isEmpty ? nil : String(value)
    }

    private func decode(data: Data, charset: String) -> String? {
        let normalized = charset.lowercased().replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "_", with: "")
        switch normalized {
        case "utf8":
            return String(data: data, encoding: .utf8)
        case "gb18030", "gbk", "gb2312", "cp936", "euccn":
            let cfEncoding = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
        case "big5", "big5hkscs", "cp950":
            let cfEncoding = CFStringEncoding(CFStringEncodings.big5.rawValue)
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            return String(data: data, encoding: String.Encoding(rawValue: nsEncoding))
        case "iso88591", "latin1", "cp1252", "windows1252":
            return String(data: data, encoding: .isoLatin1)
        default:
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
            if cfEnc != kCFStringEncodingInvalidId {
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
                return String(data: data, encoding: String.Encoding(rawValue: nsEnc))
            }
            return nil
        }
    }
}
