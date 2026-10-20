import Foundation
import CoreFoundation

/// Java/Legado charset bridge for JavaScriptCore.
///
/// Android book sources routinely call `new java.lang.String(bytes, "GBK")`,
/// `java.encodeURI(value, "gbk")`, `URLEncoder.encode(value, "GB18030")`, or
/// Big5 variants used by traditional-Chinese sites. JavaScriptCore only maps
/// UTF-8/UTF-16/ASCII/Latin-1 through `String.Encoding`, so the CJK encodings
/// are routed through CoreFoundation here. One implementation keeps the whole
/// bridge consistent: previously `encodeURI` supported GBK while `decodeURI`,
/// `URLEncoder`, and `URLDecoder` silently fell back to UTF-8.
enum LegadoCharset {
    private static let gb18030Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        )
    )

    private static let big5Encoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue)
        )
    )

    /// Canonical name used by the encode/decode switches below.
    static func canonicalName(_ charset: String?) -> String {
        guard let charset else { return "utf8" }
        let name = charset
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        switch name {
        case "", "utf8", "utf":
            return "utf8"
        case "utf16", "utf16le", "unicode", "unicodele":
            return "utf16le"
        case "utf16be", "unicodebe":
            return "utf16be"
        case "ascii", "usascii", "iso646us", "ansix341968":
            return "ascii"
        case "latin1", "iso88591", "l1", "cp819", "ibm819":
            return "latin1"
        case "gb18030":
            return "gb18030"
        case "gbk", "cp936", "ms936", "windows936", "xgbk", "euccn", "gb2312", "gbk2312":
            return "gbk"
        case "big5", "cp950", "big5hkscs", "xbig5", "windows950":
            return "big5"
        default:
            if name.hasPrefix("gb18030") { return "gb18030" }
            if name.hasPrefix("gbk") || name.hasPrefix("gb2312") || name.hasPrefix("cp936")
                || name.hasPrefix("euccn") {
                return "gbk"
            }
            if name.hasPrefix("big5") || name.hasPrefix("cp950") { return "big5" }
            return "utf8"
        }
    }

    /// Encode a Swift string with the charset name used by a Legado source.
    ///
    /// GB18030 is a strict superset of GBK and produces identical two-byte
    /// codes for the GBK repertoire, so it backs both "GBK" and "GB18030"
    /// requests. That matches the previous `encodeGbkData` behaviour and
    /// keeps rare CJK characters encodable instead of degrading to `?`.
    static func encode(_ value: String, charset: String?) -> Data? {
        switch canonicalName(charset) {
        case "utf8":
            return value.data(using: .utf8)
        case "utf16le":
            return value.data(using: .utf16LittleEndian)
        case "utf16be":
            return value.data(using: .utf16BigEndian)
        case "ascii":
            return value.data(using: .ascii)
        case "latin1":
            return value.data(using: .isoLatin1)
        case "gbk", "gb18030":
            return value.data(using: gb18030Encoding)
        case "big5":
            return value.data(using: big5Encoding)
        default:
            return value.data(using: .utf8)
        }
    }

    static func decode(_ data: Data, charset: String?) -> String? {
        switch canonicalName(charset) {
        case "utf8":
            return String(data: data, encoding: .utf8)
        case "utf16le":
            return String(data: data, encoding: .utf16LittleEndian)
        case "utf16be":
            return String(data: data, encoding: .utf16BigEndian)
        case "ascii":
            return String(data: data, encoding: .ascii)
        case "latin1":
            return String(data: data, encoding: .isoLatin1)
        case "gbk", "gb18030":
            return String(data: data, encoding: gb18030Encoding)
        case "big5":
            return String(data: data, encoding: big5Encoding)
        default:
            return String(data: data, encoding: .utf8)
        }
    }

    /// RFC 3986-style percent encoding over the charset bytes.
    ///
    /// `extraAllowed` lets `java.urlEncode` keep Java URLEncoder's `*` while
    /// `java.encodeURI` keeps the RFC unreserved `-._~` set.
    static func percentEncode(
        _ value: String,
        charset: String?,
        extraAllowed: String = "-._~"
    ) -> String? {
        guard let data = encode(value, charset: charset) else { return nil }
        var allowed = Set<UInt8>()
        for byte in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789".utf8 {
            allowed.insert(byte)
        }
        for byte in extraAllowed.utf8 { allowed.insert(byte) }

        var output = String()
        output.reserveCapacity(data.count * 3)
        for byte in data {
            if allowed.contains(byte) {
                output.unicodeScalars.append(UnicodeScalar(byte))
            } else {
                output += String(format: "%%%02X", byte)
            }
        }
        return output
    }

    /// Decode percent escapes into bytes and interpret each byte run with the
    /// requested charset. Literal characters outside `%XX` stay literal, which
    /// matches Java URLDecoder instead of re-encoding already-decoded text.
    static func percentDecode(
        _ value: String,
        charset: String?,
        plusAsSpace: Bool = false
    ) -> String? {
        var output = String()
        output.reserveCapacity(value.count)
        var pending: [UInt8] = []
        let scalars = Array(value.unicodeScalars)
        var index = 0

        func flushPending() {
            guard !pending.isEmpty else { return }
            if let decoded = decode(Data(pending), charset: charset) {
                output.append(decoded)
            } else {
                output.append(String(decoding: pending, as: UTF8.self))
            }
            pending.removeAll(keepingCapacity: true)
        }

        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "%", index + 2 < scalars.count,
               let high = hexValue(scalars[index + 1]),
               let low = hexValue(scalars[index + 2]) {
                pending.append((high << 4) | low)
                index += 3
                continue
            }
            if plusAsSpace, scalar == "+" {
                flushPending()
                output.append(" ")
                index += 1
                continue
            }
            flushPending()
            output.unicodeScalars.append(scalar)
            index += 1
        }
        flushPending()
        return output
    }

    private static func hexValue(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar.value {
        case 48...57: return UInt8(scalar.value - 48)          // 0-9
        case 65...70: return UInt8(scalar.value - 65 + 10)     // A-F
        case 97...102: return UInt8(scalar.value - 97 + 10)    // a-f
        default: return nil
        }
    }
}