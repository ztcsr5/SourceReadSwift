import CoreFoundation
import Foundation

/// A decoded illustration returned by `ruleContent.imageDecode`.
struct InlineImagePayload: Equatable {
    let data: Data
    let fileExtension: String
}

/// How an `imageDecode` result should be interpreted.
enum InlineImageDecodingOutcome: Equatable {
    /// The result is an ordinary URL or an unrecognized rule value.
    case notInline
    /// The result is an image payload that can be registered for the reader.
    case decoded(InlineImagePayload)
    /// The result looks like an inline image payload but cannot be used.
    case invalid(String)
}

/// Decodes the payload shapes Android Legado book sources return from
/// `ruleContent.imageDecode`.
///
/// Legado evaluates the rule once per `[img]` URL. It may return:
/// - a replacement URL, handled by `ContentParser`'s existing URL rewrite;
/// - a `data:image/...;base64,...` URI;
/// - a raw base64 blob;
/// - a byte array (`java.ajaxBytes`, `java.base64DecodeToByteArray`,
///   `Uint8Array`), which JavaScriptCore serializes to JSON.
///
/// Only payloads whose first bytes identify a bitmap format are accepted.
/// Ordinary URLs and arbitrary JSON rule output therefore stay on the
/// existing URL path instead of becoming broken `data:` images.
enum InlineImageDecoder {
    /// Upper bound for one decoded illustration. Comic strips can be large;
    /// this caps a malformed rule without rejecting normal pages.
    static let maximumByteCount = 32 * 1024 * 1024

    static func decode(_ raw: String) -> InlineImageDecodingOutcome {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .notInline }
        let text = unwrappingQuotes(trimmed)
        guard !text.isEmpty else { return .notInline }

        let lowercased = text.lowercased()
        if lowercased.hasPrefix("data:") {
            guard let base64 = dataURIPayload(from: text) else {
                return .invalid("data URI is not base64 encoded")
            }
            return decodeBase64(base64, source: "data URI")
        }
        if lowercased.hasPrefix("base64,") {
            return decodeBase64(String(text.dropFirst("base64,".count)), source: "base64 prefix")
        }
        if text.hasPrefix("[") || text.hasPrefix("{") {
            if let bytes = byteArray(fromJSON: text) {
                return payload(from: Data(bytes), source: "byte array")
            }
            if looksLikeNumericJSON(text) {
                return .invalid("byte array contains no usable bytes")
            }
            return .notInline
        }
        if looksLikeBase64(text) {
            return decodeBase64(text, source: "raw base64")
        }
        return .notInline
    }

    static func imageFileExtension(for data: Data) -> String? {
        let bytes = [UInt8](data.prefix(16))
        guard !bytes.isEmpty else { return nil }

        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            return "png"
        }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "jpg"
        }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) {
            return "gif"
        }
        if bytes.count >= 12,
           ascii(bytes[0..<4]) == "RIFF",
           ascii(bytes[8..<12]) == "WEBP" {
            return "webp"
        }
        if bytes.starts(with: [0x42, 0x4D]) {
            return "bmp"
        }
        if bytes.starts(with: [0x49, 0x49, 0x2A, 0x00]) || bytes.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "tiff"
        }
        if bytes.count >= 12, ascii(bytes[4..<8]) == "ftyp" {
            let brand = ascii(bytes[8..<12])
            if ["heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains(brand) {
                return "heic"
            }
            if ["avif", "avis"].contains(brand) {
                return "avif"
            }
        }
        return nil
    }

    private static func dataURIPayload(from text: String) -> String? {
        guard let comma = text.firstIndex(of: ",") else { return nil }
        let metadata = text[..<comma].lowercased()
        guard metadata.contains(";base64") else { return nil }
        let payload = String(text[text.index(after: comma)...])
        return payload.removingPercentEncoding ?? payload
    }

    private static func decodeBase64(_ raw: String, source: String) -> InlineImageDecodingOutcome {
        var compact = raw.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return .invalid("\(source) is empty") }
        guard compact.count <= maximumByteCount * 4 / 3 + 16 else {
            return .invalid("\(source) is too large")
        }
        compact = compact
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = compact.count % 4
        if remainder != 0 {
            compact += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: compact) else {
            return .invalid("\(source) is not valid base64")
        }
        return payload(from: data, source: source)
    }

    private static func payload(from data: Data, source: String) -> InlineImageDecodingOutcome {
        guard !data.isEmpty else { return .invalid("\(source) decoded to zero bytes") }
        guard data.count <= maximumByteCount else {
            return .invalid("\(source) exceeds the inline image limit")
        }
        guard let fileExtension = imageFileExtension(for: data) else {
            return .invalid("\(source) is not a supported image format")
        }
        return .decoded(InlineImagePayload(data: data, fileExtension: fileExtension))
    }

    private static func byteArray(fromJSON text: String) -> [UInt8]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        guard let bytes = byteArray(fromJSONObject: object), bytes.count >= 12 else { return nil }
        return bytes
    }

    private static func byteArray(fromJSONObject object: Any) -> [UInt8]? {
        if let array = object as? [Any] {
            return byteValues(from: array)
        }
        if let dictionary = object as? [String: Any] {
            if let nested = dictionary["bytes"] ?? dictionary["data"] {
                return byteArray(fromJSONObject: nested)
            }
            let numericKeys = dictionary.keys.compactMap { Int($0) }.sorted()
            guard !numericKeys.isEmpty, numericKeys == Array(0..<numericKeys.count) else { return nil }
            let values = numericKeys.compactMap { dictionary[String($0)] }
            guard values.count == numericKeys.count else { return nil }
            return byteValues(from: values)
        }
        return nil
    }

    private static func byteValues(from values: [Any]) -> [UInt8]? {
        guard !values.isEmpty else { return [] }
        var result: [UInt8] = []
        result.reserveCapacity(values.count)
        for value in values {
            guard let number = value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            guard double.isFinite,
                  double.rounded(.towardZero) == double,
                  double >= 0,
                  double <= 255 else { return nil }
            result.append(UInt8(double))
        }
        return result
    }

    private static func looksLikeNumericJSON(_ text: String) -> Bool {
        if text.hasPrefix("[") {
            return text.range(of: #"-?\d"#, options: .regularExpression) != nil
        }
        return text.range(of: #""\d+"\s*:\s*-?\d"#, options: .regularExpression) != nil
    }

    private static func looksLikeBase64(_ text: String) -> Bool {
        let compact = text.filter { !$0.isWhitespace }
        guard compact.count >= 32 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=_-")
        return compact.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func unwrappingQuotes(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, let last = text.last else { return text }
        if (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            return String(text.dropFirst().dropLast())
        }
        return text
    }

    private static func ascii<C: Collection>(_ bytes: C) -> String where C.Element == UInt8 {
        String(decoding: bytes, as: UTF8.self)
    }
}
