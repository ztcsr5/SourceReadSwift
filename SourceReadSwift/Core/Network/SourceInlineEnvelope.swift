import Foundation

/// Decodes a source's local data URL as inert response bytes, with no HTTP request.
enum SourceInlineEnvelope {
    private static let maximumBodyBytes = 4 * 1024 * 1024
    private static let maximumMetadataBytes = 256
    private static let maximumAddressBytes = maximumBodyBytes * 4 + maximumMetadataBytes

    static func isAddress(_ value: String) -> Bool {
        value.prefix(5).lowercased() == "data:"
    }

    static func response(for url: URL) -> Result<SourceResponse, SourceEngineError> {
        let raw = url.absoluteString
        guard raw.utf8.count <= maximumAddressBytes else { return .failure(.rule("内嵌书源数据超过大小限制")) }
        let address = raw.prefix { $0 != "#" }
        guard let separator = address.firstIndex(of: ","),
              address[..<separator].utf8.count <= maximumMetadataBytes else {
            return .failure(.rule("内嵌书源数据缺少有效的 data: 分隔符"))
        }
        let header = address[..<separator].dropFirst(5).split(separator: ";", omittingEmptySubsequences: false)
        let mediaType = normalizedMediaType(header.first ?? "")
        let flags = header.dropFirst().map { $0.lowercased() }
        let charset = flags.first(where: { $0.hasPrefix("charset=") }).flatMap {
            let value = String($0.dropFirst(8))
            return value.range(of: #"^[a-z0-9_-]{1,32}$"#, options: .regularExpression) != nil ? value : nil
        } ?? "utf-8"

        guard let bytes = percentDecode(address[address.index(after: separator)...]) else {
            return .failure(.rule("内嵌书源数据含无效的百分号编码"))
        }
        let bodyBytes: Data
        if flags.contains("base64") {
            let compact = Data(bytes.filter { $0 != 9 && $0 != 10 && $0 != 13 && $0 != 32 })
            guard let decoded = Data(base64Encoded: compact) else {
                return .failure(.rule("内嵌书源数据的 Base64 无效"))
            }
            bodyBytes = decoded
        } else {
            bodyBytes = bytes
        }
        guard bodyBytes.count <= maximumBodyBytes else { return .failure(.rule("内嵌书源数据超过 4 MiB")) }
        let body = LegadoCharset.decode(bodyBytes, charset: charset) ?? String(decoding: bodyBytes, as: UTF8.self)
        return .success(SourceResponse(url: url, statusCode: 200,
            headers: ["Content-Type": "\(mediaType); charset=\(charset)"], body: body, data: bodyBytes))
    }

    private static func normalizedMediaType(_ raw: Substring) -> String {
        let value = raw.lowercased()
        // Some sources use a stage name (detailsUrl), not an Internet media type.
        guard value.range(of: #"^[a-z0-9][a-z0-9.+_-]{0,39}/[a-z0-9][a-z0-9.+_-]{0,63}$"#,
                          options: .regularExpression) != nil else { return "text/plain" }
        return value
    }

    private static func percentDecode(_ payload: Substring) -> Data? {
        var encoded = payload.utf8.makeIterator()
        var decoded = Data()
        decoded.reserveCapacity(min(payload.utf8.count, maximumBodyBytes))
        while let byte = encoded.next() {
            if byte != 37 {
                decoded.append(byte)
                continue
            }
            guard let first = encoded.next(), let second = encoded.next(),
                  let high = hexDigit(first), let low = hexDigit(second) else { return nil }
            decoded.append(high << 4 | low)
        }
        return decoded
    }

    private static func hexDigit(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: return byte - 48
        case 65...70: return byte - 55
        case 97...102: return byte - 87
        default: return nil
        }
    }
}
