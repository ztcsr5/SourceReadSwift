import Foundation
import JavaScriptCore
import CoreFoundation
import CryptoKit
import CryptoSwift
import ZIPFoundation
import CommonCrypto
import Compression
import Security

/// Native services required by Legado JavaScript sources.  All filesystem access is
/// constrained to the app container; relative paths live under Documents/LegadoSandbox.
final class LegadoHostServices {
    private let executionContext: RuleExecutionContext
    private let fileManager: FileManager
    let sandboxURL: URL
    private let queryTTFLock = NSLock()
    private var queryTTFObjects: [String: QueryTTF] = [:]
    private var queryTTFSequence = 0

    init(executionContext: RuleExecutionContext, fileManager: FileManager = .default) {
        self.executionContext = executionContext
        self.fileManager = fileManager
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.sandboxURL = documents.appendingPathComponent("LegadoSandbox", isDirectory: true)
        try? fileManager.createDirectory(at: sandboxURL, withIntermediateDirectories: true)
    }

    // MARK: - Cookie

    func cookie(url rawURL: String, key: String?) -> String {
        let contextHeader = executionContext.string(for: "cookieHeader")
        guard let url = URL(string: rawURL),
              let cookies = HTTPCookieStorage.shared.cookies(for: url) else {
            if let key, !key.isEmpty {
                return CookieHeaderParser.pairs(fromCookieHeader: contextHeader)
                    .first(where: { $0.name == key })?.value ?? ""
            }
            return contextHeader
        }
        if let key, !key.isEmpty {
            return CookieHeaderParser.pairs(fromCookieHeader: CookieHeaderParser.merge(
                HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? "",
                into: contextHeader.nilIfEmpty
            )).first(where: { $0.name == key })?.value ?? ""
        }
        let stored = HTTPCookie.requestHeaderFields(with: cookies)["Cookie"] ?? ""
        return CookieHeaderParser.merge(stored, into: contextHeader.nilIfEmpty)
    }

    @discardableResult
    func setCookie(url rawURL: String, value: String) -> String {
        let existing = executionContext.string(for: "cookieHeader").nilIfEmpty
        // `cookie.setCookie` receives a request Cookie header, not a single
        // Set-Cookie response field. Parse every pair and ignore attributes
        // such as Path/Domain so `sid=1; theme=dark` keeps both values.
        let pairs = CookieHeaderParser.pairs(fromCookieHeader: value)
            .filter { !Self.cookieAttributes.contains($0.name.lowercased()) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        let merged = CookieHeaderParser.merge(pairs.isEmpty ? value : pairs, into: existing)
        executionContext.setValue(merged, for: "cookieHeader")
        guard let url = URL(string: rawURL), !value.isEmpty else { return merged }
        for pair in CookieHeaderParser.pairs(fromCookieHeader: value)
            .filter({ !Self.cookieAttributes.contains($0.name.lowercased()) }) {
            let item = "\(pair.name)=\(pair.value); Path=/"
            HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": item], for: url)
                .forEach(HTTPCookieStorage.shared.setCookie)
        }
        return merged
    }

    private static let cookieAttributes: Set<String> = [
        "path", "domain", "expires", "max-age", "secure", "httponly", "samesite"
    ]

    // MARK: - Text/encoding

    func encodeURI(_ value: String, charset: String? = nil) -> String {
        let normalized = charset?.lowercased() ?? "utf-8"
        if normalized.contains("gbk") || normalized.contains("gb2312") || normalized.contains("gb18030") {
            let encoding = Self.gbkEncoding
            guard let data = value.data(using: encoding) else { return value }
            return data.map { byte in
                let scalar = UnicodeScalar(byte)
                if CharacterSet.alphanumerics.contains(scalar) || "-._~".utf8.contains(byte) {
                    return String(UnicodeScalar(byte))
                }
                return String(format: "%%%02X", byte)
            }.joined()
        }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    func utf8ToGbk(_ value: String) -> NSArray {
        guard let data = value.data(using: Self.gbkEncoding) else { return [] }
        return data.map { NSNumber(value: $0) } as NSArray
    }

    func decodeText(_ data: Data, charset: String?) -> String {
        let name = charset?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let encoding: String.Encoding
        if name.contains("gbk") || name.contains("gb2312") || name.contains("gb18030") {
            encoding = Self.gbkEncoding
        } else if name.contains("utf-16") {
            encoding = .utf16
        } else if name.contains("big5") {
            encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue)))
        } else {
            encoding = .utf8
        }
        return String(data: data, encoding: encoding)
            ?? String(data: data, encoding: .utf8)
            ?? ""
    }

    func htmlFormat(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    // MARK: - AES

    func aes(
        operation: String,
        input: Any?,
        key: Any?,
        transformation: String,
        iv: Any?
    ) -> Any {
        do {
            let keyBytes = bytes(from: key)
            let ivBytes = bytes(from: iv)
            let mode: BlockMode = transformation.uppercased().contains("ECB")
                ? ECB()
                : CBC(iv: normalizedIV(ivBytes))
            let padding: Padding = transformation.uppercased().contains("NOPADDING") ? .noPadding : .pkcs7
            let cipher = try AES(key: normalizedKey(keyBytes), blockMode: mode, padding: padding)
            let isDecode = operation.localizedCaseInsensitiveContains("decode")
            var payload = bytes(from: input)
            if operation.localizedCaseInsensitiveContains("base64decode"),
               let decoded = Data(base64Encoded: Self.normalizedBase64(RuleExecutionContext.bridgeString(input))) {
                payload = Array(decoded)
            }
            let output = try isDecode ? cipher.decrypt(payload) : cipher.encrypt(payload)
            if operation.localizedCaseInsensitiveContains("base64") && !isDecode {
                let encoded = Data(output).base64EncodedString()
                if operation.localizedCaseInsensitiveContains("bytearray") {
                    return Array(encoded.utf8).map { NSNumber(value: $0) } as NSArray
                }
                return encoded
            }
            if operation.localizedCaseInsensitiveContains("bytearray") {
                return output.map { NSNumber(value: $0) } as NSArray
            }
            return String(data: Data(output), encoding: .utf8) ?? Data(output).base64EncodedString()
        } catch {
            executionContext.log("AES failed: \(error.localizedDescription)")
            return operation.localizedCaseInsensitiveContains("bytearray") ? ([] as NSArray) : ""
        }
    }

    // MARK: - RSA

    /// Legado's RSA helpers exchange base64 strings.  Accept both PEM and
    /// bare DER keys and keep failures deterministic (empty string) so a source
    /// can fall back to its alternate endpoint instead of crashing JSCore.
    func rsa(operation: String, value: String, key: String) -> String {
        let isPrivate = operation.localizedCaseInsensitiveContains("private") ||
            (operation.localizedCaseInsensitiveContains("decrypt") &&
             !operation.localizedCaseInsensitiveContains("decryptWithPublic"))
        let keyData: Data
        if key.contains("BEGIN") {
            let body = key.components(separatedBy: .newlines).filter { !$0.contains("BEGIN") && !$0.contains("END") }.joined()
            guard let data = Data(base64Encoded: body) else { return "" }
            keyData = data
        } else if let data = Data(base64Encoded: Self.normalizedBase64(key)) {
            keyData = data
        } else { return "" }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: isPrivate ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: rsaKeySizeBits(keyData)
        ]
        let secKey: SecKey?
        if let direct = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil) {
            secKey = direct
        } else if !isPrivate, let raw = unwrapRSAPublicKey(keyData) {
            var fallback = attributes
            fallback[kSecAttrKeySizeInBits] = rsaKeySizeBits(raw)
            secKey = SecKeyCreateWithData(raw as CFData, fallback as CFDictionary, nil)
        } else if isPrivate, let raw = unwrapRSAPrivateKey(keyData) {
            var fallback = attributes
            fallback[kSecAttrKeySizeInBits] = rsaKeySizeBits(raw)
            secKey = SecKeyCreateWithData(raw as CFData, fallback as CFDictionary, nil)
        } else {
            secKey = nil
        }
        guard let secKey else { return "" }
        let algorithm: SecKeyAlgorithm = .rsaEncryptionPKCS1
        let decrypt = operation.localizedCaseInsensitiveContains("decrypt")
        if decrypt {
            guard let cipher = Data(base64Encoded: Self.normalizedBase64(value)), SecKeyIsAlgorithmSupported(secKey, .decrypt, algorithm),
                  let clear = SecKeyCreateDecryptedData(secKey, algorithm, cipher as CFData, nil) as Data? else { return "" }
            return String(data: clear, encoding: .utf8) ?? clear.base64EncodedString()
        }
        guard let clear = value.data(using: .utf8), SecKeyIsAlgorithmSupported(secKey, .encrypt, algorithm),
              let cipher = SecKeyCreateEncryptedData(secKey, algorithm, clear as CFData, nil) as Data? else { return "" }
        return cipher.base64EncodedString()
    }

    // MARK: - Legado asymmetric crypto and signatures

    /// Create an RSA-compatible operation using Apple's Security framework.
    /// Legado exchanges strings as Base64 at this boundary, which keeps binary
    /// ciphertext/signatures lossless through JavaScriptCore.
    func asymmetric(operation: String, transformation: String, value: Any?, key: String) -> String {
        guard let secKey = makeSecKey(key: key, isPrivate: operation.localizedCaseInsensitiveContains("private") ||
                                      operation.localizedCaseInsensitiveContains("decrypt"),
                                      operation: operation) else {
            executionContext.recordBridgeFailure("java.createAsymmetricCrypto", message: "invalid RSA key")
            return ""
        }
        let decrypt = operation.localizedCaseInsensitiveContains("decrypt")
        let payload: Data
        if decrypt {
            let payloadText = RuleExecutionContext.bridgeString(value)
            guard let decoded = Data(base64Encoded: Self.normalizedBase64(payloadText)) else {
                executionContext.recordBridgeFailure("java.createAsymmetricCrypto", message: "ciphertext is not Base64")
                return ""
            }
            payload = decoded
        } else {
            payload = data(from: value)
        }
        let algorithm = rsaEncryptionAlgorithm(transformation)
        guard SecKeyIsAlgorithmSupported(secKey, decrypt ? .decrypt : .encrypt, algorithm) else {
            executionContext.recordBridgeFailure("java.createAsymmetricCrypto", message: "unsupported RSA transformation")
            return ""
        }
        let result: Data?
        if decrypt {
            result = SecKeyCreateDecryptedData(secKey, algorithm, payload as CFData, nil) as Data?
        } else {
            result = SecKeyCreateEncryptedData(secKey, algorithm, payload as CFData, nil) as Data?
        }
        guard let result else {
            executionContext.recordBridgeFailure("java.createAsymmetricCrypto", message: decrypt ? "RSA decrypt failed" : "RSA encrypt failed")
            return ""
        }
        return decrypt ? (String(data: result, encoding: .utf8) ?? result.base64EncodedString()) : result.base64EncodedString()
    }

    func sign(operation: String, algorithmName: String, value: Any?, key: String, signature: Any? = nil) -> String {
        let verify = operation.localizedCaseInsensitiveContains("verify")
        let isPrivate = !verify
        guard let secKey = makeSecKey(key: key, isPrivate: isPrivate, operation: operation) else {
            executionContext.recordBridgeFailure("java.createSign", message: "invalid RSA key")
            return verify ? "false" : ""
        }
        let message = data(from: value)
        let secAlgorithm = rsaSignatureAlgorithm(algorithmName)
        guard SecKeyIsAlgorithmSupported(secKey, verify ? .verify : .sign, secAlgorithm) else {
            executionContext.recordBridgeFailure("java.createSign", message: "unsupported signature algorithm (algorithmName)")
            return verify ? "false" : ""
        }
        if verify {
            let encoded = RuleExecutionContext.bridgeString(signature)
            let signatureData: Data?
            if operation.localizedCaseInsensitiveContains("hex") {
                signatureData = Self.dataFromHex(encoded)
            } else {
                signatureData = Data(base64Encoded: Self.normalizedBase64(encoded))
            }
            guard let signatureData else { return "false" }
            let valid = SecKeyVerifySignature(secKey, secAlgorithm, message as CFData, signatureData as CFData, nil)
            return valid ? "true" : "false"
        }
        guard let output = SecKeyCreateSignature(secKey, secAlgorithm, message as CFData, nil) as Data? else {
            executionContext.recordBridgeFailure("java.createSign", message: "RSA signing failed")
            return ""
        }
        if operation.localizedCaseInsensitiveContains("hex") {
            return output.map { String(format: "%02x", $0) }.joined()
        }
        return output.base64EncodedString()
    }

    private func makeSecKey(key: String, isPrivate: Bool, operation: String) -> SecKey? {
        let keyData: Data
        if key.contains("BEGIN") {
            let body = key.components(separatedBy: .newlines)
                .filter { !$0.contains("BEGIN") && !$0.contains("END") }
                .joined()
            guard let data = Data(base64Encoded: Self.normalizedBase64(body)) else { return nil }
            keyData = data
        } else if let data = Data(base64Encoded: Self.normalizedBase64(key)) {
            keyData = data
        } else { return nil }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: isPrivate ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: rsaKeySizeBits(keyData)
        ]
        if let direct = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, nil) { return direct }
        if !isPrivate, let raw = unwrapRSAPublicKey(keyData) {
            var fallback = attributes
            fallback[kSecAttrKeySizeInBits] = rsaKeySizeBits(raw)
            return SecKeyCreateWithData(raw as CFData, fallback as CFDictionary, nil)
        }
        if isPrivate, let raw = unwrapRSAPrivateKey(keyData) {
            var fallback = attributes
            fallback[kSecAttrKeySizeInBits] = rsaKeySizeBits(raw)
            return SecKeyCreateWithData(raw as CFData, fallback as CFDictionary, nil)
        }
        return nil
    }

    private func rsaKeySizeBits(_ data: Data) -> Int {
        let bytes = Array(data)
        guard bytes.count >= 8 else { return max(512, bytes.count * 8) }
        for index in 0..<(bytes.count - 2) where bytes[index] == 0x02 {
            guard let (length, header) = derLength(bytes, at: index + 1),
                  length >= 64, index + 1 + header + length <= bytes.count else { continue }
            let start = index + 1 + header
            let leading = bytes[start] == 0 ? 1 : 0
            return max(512, (length - leading) * 8)
        }
        return max(512, bytes.count * 8)
    }

    private func derLength(_ bytes: [UInt8], at index: Int) -> (length: Int, header: Int)? {
        guard index < bytes.count else { return nil }
        let first = bytes[index]
        if first & 0x80 == 0 { return (Int(first), 1) }
        let count = Int(first & 0x7f)
        guard count > 0, count <= 4, index + count < bytes.count else { return nil }
        var length = 0
        for offset in 0..<count { length = (length << 8) | Int(bytes[index + 1 + offset]) }
        return (length, 1 + count)
    }

    /// Extract the PKCS#1 RSA private-key sequence nested in a PKCS#8
    /// PrivateKeyInfo OCTET STRING.  The scan is intentionally conservative:
    /// it only accepts a sequence whose first two children are INTEGERs and
    /// whose second integer is large enough to be an RSA modulus.
    private func unwrapRSAPrivateKey(_ data: Data) -> Data? {
        let bytes = Array(data)
        guard bytes.count > 16 else { return nil }
        for index in 0..<(bytes.count - 4) where bytes[index] == 0x30 {
            guard let (sequenceLength, sequenceHeader) = derLength(bytes, at: index + 1),
                  index + 1 + sequenceHeader + sequenceLength <= bytes.count else { continue }
            let start = index + 1 + sequenceHeader
            guard bytes[start] == 0x02,
                  let (_, firstHeader) = derLength(bytes, at: start + 1) else { continue }
            guard let (firstLength, _) = derLength(bytes, at: start + 1) else { continue }
            let second = start + 1 + firstHeader + firstLength
            guard second < bytes.count, bytes[second] == 0x02,
                  let (modulusLength, _) = derLength(bytes, at: second + 1),
                  modulusLength >= 64 else { continue }
            return Data(bytes[index..<(index + 1 + sequenceHeader + sequenceLength)])
        }
        return nil
    }

    /// Preserve binary arguments passed by Java/Legado byte-array APIs. A
    /// Swift String remains UTF-8, while NSArray/Data/JSValue arrays are
    /// interpreted as unsigned bytes instead of their JSON description.
    private func data(from value: Any?) -> Data {
        if value is NSArray || value is [Any] || value is [NSNumber] || value is [UInt8] || value is Data || value is JSValue {
            return Data(bytes(from: value))
        }
        return Data(RuleExecutionContext.bridgeString(value).utf8)
    }

    private static func dataFromHex(_ value: String) -> Data? {
        let text = value.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !text.isEmpty, text.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<end], radix: 16) else { return nil }
            bytes.append(byte)
            index = end
        }
        return Data(bytes)
    }

    private func unwrapRSAPublicKey(_ data: Data) -> Data? {
        let bytes = Array(data)
        guard bytes.count > 24 else { return nil }
        for index in 0..<(bytes.count - 1) where bytes[index] == 0x03 {
            let lengthByte = bytes[index + 1]
            var header = 2
            var length = Int(lengthByte)
            if lengthByte & 0x80 != 0 {
                let count = Int(lengthByte & 0x7f)
                guard count > 0, count <= 4, index + 2 + count <= bytes.count else { continue }
                header += count; length = 0
                for item in bytes[(index + 2)..<(index + 2 + count)] { length = (length << 8) | Int(item) }
            }
            let payloadStart = index + header
            guard payloadStart < bytes.count, length >= 1, payloadStart + length <= bytes.count,
                  bytes[payloadStart] == 0 else { continue }
            return Data(bytes[(payloadStart + 1)..<(payloadStart + length)])
        }
        return nil
    }

    private func rsaEncryptionAlgorithm(_ transformation: String) -> SecKeyAlgorithm {
        let normalized = transformation.lowercased().replacingOccurrences(of: "-", with: "")
        if normalized.contains("oaep") {
            if normalized.contains("sha256") { return .rsaEncryptionOAEPSHA256 }
            if normalized.contains("sha512") { return .rsaEncryptionOAEPSHA512 }
            return .rsaEncryptionOAEPSHA1
        }
        return .rsaEncryptionPKCS1
    }

    private func rsaSignatureAlgorithm(_ algorithm: String) -> SecKeyAlgorithm {
        let normalized = algorithm.lowercased().replacingOccurrences(of: "-", with: "")
        if normalized.contains("pss") {
            if normalized.contains("512") { return .rsaSignatureMessagePSSSHA512 }
            if normalized.contains("384") { return .rsaSignatureMessagePSSSHA384 }
            if normalized.contains("256") { return .rsaSignatureMessagePSSSHA256 }
            return .rsaSignatureMessagePSSSHA1
        }
        if normalized.contains("512") { return .rsaSignatureMessagePKCS1v15SHA512 }
        if normalized.contains("384") { return .rsaSignatureMessagePKCS1v15SHA384 }
        if normalized.contains("256") { return .rsaSignatureMessagePKCS1v15SHA256 }
        if normalized.contains("224") { return .rsaSignatureMessagePKCS1v15SHA224 }
        if normalized.contains("sha1") { return .rsaSignatureMessagePKCS1v15SHA1 }
        return .rsaSignatureMessagePKCS1v15SHA256
    }

    // MARK: - queryTTF

    func queryTTFParse(_ value: Any?) -> String {
        var bytes = bytes(from: value)
        // JS sources commonly pass a Base64 font string (or a data: URL)
        // while Java callers pass a byte array. Decode only when the raw
        // argument does not already look like an sfnt payload.
        if !looksLikeSFNT(bytes) {
            let text = RuleExecutionContext.bridgeString(value)
            let encoded = text.range(of: "base64,", options: [.caseInsensitive])
                .map { String(text[$0.upperBound...]) } ?? text
            if let decoded = Data(base64Encoded: Self.normalizedBase64(encoded)) {
                bytes = Array(decoded)
            }
        }
        guard !bytes.isEmpty else {
            executionContext.recordBridgeFailure("java.queryTTF", message: "empty font payload")
            return ""
        }
        let object = QueryTTF(data: Data(bytes))
        queryTTFLock.lock(); defer { queryTTFLock.unlock() }
        queryTTFSequence += 1
        let handle = "ttf-\(queryTTFSequence)"
        queryTTFObjects[handle] = object
        if queryTTFObjects.count > 8 { queryTTFObjects.removeValue(forKey: queryTTFObjects.keys.sorted().first ?? "") }
        return handle
    }

    private func looksLikeSFNT(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 4 else { return false }
        return (bytes[0] == 0x00 && bytes[1] == 0x01 && bytes[2] == 0x00 && bytes[3] == 0x00)
            || Array(bytes.prefix(4)) == Array("OTTO".utf8)
            || Array(bytes.prefix(4)) == Array("true".utf8)
            || Array(bytes.prefix(4)) == Array("typ1".utf8)
    }

    func queryTTFGlyfByUnicode(_ handle: String, unicode: Int) -> String {
        queryTTFLock.lock(); let value = queryTTFObjects[handle]?.getGlyfByUnicode(unicode) ?? ""; queryTTFLock.unlock(); return value
    }

    func queryTTFUnicodeByGlyf(_ handle: String, glyph: String) -> Int {
        queryTTFLock.lock(); let value = queryTTFObjects[handle]?.getUnicodeByGlyf(glyph) ?? 0; queryTTFLock.unlock(); return value
    }

    func queryTTFGlyfIdByUnicode(_ handle: String, unicode: Int) -> Int {
        queryTTFLock.lock(); let value = queryTTFObjects[handle]?.getGlyfIdByUnicode(unicode) ?? 0; queryTTFLock.unlock(); return value
    }

    func queryTTFIsBlank(_ handle: String, unicode: Int) -> Bool {
        queryTTFLock.lock(); let value = queryTTFObjects[handle]?.isBlankUnicode(unicode) ?? false; queryTTFLock.unlock(); return value
    }

    // Captcha recognition is intentionally not guessed.  Sources can provide
    // a user-entered value through java.put("captcha:<url>", value); absent
    // that value we return an empty string and leave an actionable diagnostic.
    func verificationCode(imageURL: String) -> String {
        let cached = executionContext.get("captcha:\(imageURL)")
        if !cached.isEmpty { return cached }
        executionContext.recordBridgeFailure("java.getVerificationCode", message: "verification-required")
        return ""
    }

    /// Generic raw-byte cipher bridge used by CryptoJS WordArray shims and by
    /// Javax.Cipher-compatible source snippets.  Keeping this separate from
    /// the legacy string helpers preserves their historical return semantics
    /// while allowing binary ciphertext to round-trip without UTF-8 loss.
    func cipher(
        operation: String,
        input: Any?,
        key: Any?,
        transformation: String,
        iv: Any?
    ) -> NSArray {
        let upper = transformation.uppercased()
        let isDecrypt = operation.localizedCaseInsensitiveContains("decrypt") ||
            operation.localizedCaseInsensitiveContains("decode")
        let kind: String = upper.contains("DESEDE") || upper.contains("TRIPLEDES") ? "3DES" :
            (upper.contains("DES") ? "DES" : "AES")
        let mode = upper.contains("/ECB") || upper.contains("ECB/") ? "ECB" : "CBC"
        let padding: String = upper.contains("NOPADDING") ? "NoPadding" :
            (upper.contains("ZEROPADDING") ? "ZeroPadding" : "PKCS7")
        var payload = bytes(from: input)
        var keyBytes = bytes(from: key)
        var ivBytes = bytes(from: iv)
        do {
            let output: [UInt8]
            if kind == "AES" {
                let blockSize = 16
                keyBytes = normalizedKey(keyBytes)
                ivBytes = Array((ivBytes + Array(repeating: 0, count: blockSize)).prefix(blockSize))
                let blockMode: BlockMode = mode == "ECB" ? ECB() : CBC(iv: ivBytes)
                let paddingMode: Padding = padding == "NoPadding" ? .noPadding :
                    (padding == "ZeroPadding" ? .zeroPadding : .pkcs7)
                let aes = try AES(key: keyBytes, blockMode: blockMode, padding: paddingMode)
                output = try isDecrypt ? aes.decrypt(payload) : aes.encrypt(payload)
            } else {
                output = try commonCrypto(
                    payload: payload,
                    key: keyBytes,
                    iv: ivBytes,
                    algorithm: kind == "3DES" ? CCAlgorithm(kCCAlgorithm3DES) : CCAlgorithm(kCCAlgorithmDES),
                    mode: mode,
                    padding: padding,
                    decrypt: isDecrypt
                )
            }
            return output.map { NSNumber(value: $0) } as NSArray
        } catch {
            executionContext.log("\(kind) cipher failed: \(error.localizedDescription)")
            return []
        }
    }

    /// CryptoJS's string-key overload uses the OpenSSL-compatible
    /// EVP_BytesToKey derivation rather than treating the passphrase as a
    /// fixed UTF-8 AES key.  Legado sources frequently return `Salted__`
    /// Base64 payloads, so keep this path separate from the raw WordArray
    /// cipher bridge.
    func cipherDecryptPassphrase(input: Any?, passphrase: Any?) -> NSArray {
        let encoded = RuleExecutionContext.bridgeString(input)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        guard let decoded = Data(base64Encoded: Self.paddedBase64(encoded)) else { return [] }
        let bytes = Array(decoded)
        let salted = bytes.count >= 16 && Array(bytes.prefix(8)) == Array("Salted__".utf8)
        let salt = salted ? Array(bytes[8..<16]) : []
        let ciphertext = salted ? Array(bytes.dropFirst(16)) : bytes
        let password = self.bytes(from: passphrase)
        guard !ciphertext.isEmpty else { return [] }

        let derived = evpBytesToKey(password: password, salt: salt, byteCount: 48)
        let key = Array(derived.prefix(32))
        let iv = Array(derived[32..<48])
        do {
            let aes = try AES(key: key, blockMode: CBC(iv: iv), padding: .pkcs7)
            let plain = try aes.decrypt(ciphertext)
            return plain.map { NSNumber(value: $0) } as NSArray
        } catch {
            executionContext.log("AES passphrase decrypt failed: \(error.localizedDescription)")
            return []
        }
    }

    /// CryptoJS passphrase encryption uses the OpenSSL-compatible salted
    /// envelope.  A fresh eight-byte salt is generated for every call; the
    /// envelope itself carries the salt so the result is portable to Android.
    func cipherEncryptPassphrase(input: Any?, passphrase: Any?) -> NSArray {
        let plaintext = bytes(from: input)
        let password = bytes(from: passphrase)
        guard !plaintext.isEmpty || !password.isEmpty else { return [] }
        var generator = SystemRandomNumberGenerator()
        let salt = (0..<8).map { _ in UInt8.random(in: 0...255, using: &generator) }
        let derived = evpBytesToKey(password: password, salt: salt, byteCount: 48)
        let key = Array(derived.prefix(32))
        let iv = Array(derived[32..<48])
        do {
            let aes = try AES(key: key, blockMode: CBC(iv: iv), padding: .pkcs7)
            let ciphertext = try aes.encrypt(plaintext)
            return (Array("Salted__".utf8) + salt + ciphertext)
                .map { NSNumber(value: $0) } as NSArray
        } catch {
            executionContext.log("AES passphrase encrypt failed: \(error.localizedDescription)")
            return []
        }
    }

    private func evpBytesToKey(password: [UInt8], salt: [UInt8], byteCount: Int) -> [UInt8] {
        var derived: [UInt8] = []
        var previous: [UInt8] = []
        while derived.count < byteCount {
            var material = previous
            material.append(contentsOf: password)
            material.append(contentsOf: salt)
            previous = Array(Insecure.MD5.hash(data: Data(material)))
            derived.append(contentsOf: previous)
        }
        return Array(derived.prefix(byteCount))
    }

    /// Inflate a zlib-wrapped byte stream for java.util.zip.InflaterInputStream.
    /// Compression is available on every supported iOS release and avoids
    /// pulling a second native zlib package into the app.
    func inflate(_ value: Any?) -> NSArray {
        let input = bytes(from: value)
        guard !input.isEmpty else { return [] }
        if let output = zlibInflate(input, rawDeflate: false) {
            return output.map { NSNumber(value: $0) } as NSArray
        }
        // Compression.framework accepts the zlib-wrapped payload used by
        // Legado.  A few sources incorrectly strip or retain the wrapper, so
        // try both representations before reporting a decode miss.
        var candidates = [input]
        if input.count > 6, input[0] == 0x78 {
            candidates.append(Array(input.dropFirst(2).dropLast(4)))
        }
        for candidate in candidates where !candidate.isEmpty {
            if #available(iOS 13.0, macOS 10.15, *) {
                // Foundation's NSData decompressor delegates to the system
                // zlib implementation and is reliable for small streams.
                if let data = try? (Data(candidate) as NSData).decompressed(using: .zlib),
                   !data.isEmpty {
                    return data.map { NSNumber(value: $0) } as NSArray
                }
            }
            if let output = inflateCandidate(candidate) {
                return output.map { NSNumber(value: $0) } as NSArray
            }
            // The one-shot API is available across all supported iOS SDKs.
            // Grow the destination until the stream fits; this avoids relying
            // on SDK-specific `compression_stream` initializers.
            var capacity = max(1024, candidate.count * 4)
            for _ in 0..<10 {
                var output = Array(repeating: UInt8(0), count: capacity)
                let decoded = candidate.withUnsafeBytes { source in
                    output.withUnsafeMutableBytes { destination in
                        compression_decode_buffer(
                            destination.bindMemory(to: UInt8.self).baseAddress!,
                            capacity,
                            source.bindMemory(to: UInt8.self).baseAddress!,
                            candidate.count,
                            nil,
                            COMPRESSION_ZLIB
                        )
                    }
                }
                if decoded > 0 {
                    output.removeLast(output.count - decoded)
                    return output.map { NSNumber(value: $0) } as NSArray
                }
                capacity *= 2
            }
        }
        executionContext.log("InflaterInputStream failed to decode payload")
        return []
    }


    /// Decode an RFC 1952 gzip stream for Android sources that explicitly use
    /// `GZIPInputStream` instead of relying on URLSession content decoding.
    /// The gzip envelope is parsed here and the raw DEFLATE payload is handed
    /// to the same bounded system decoder used by `InflaterInputStream`.
    func gunzip(_ value: Any?) -> NSArray {
        let input = bytes(from: value)
        guard let payload = gzipPayload(input) else {
            executionContext.log("GZIPInputStream rejected an invalid gzip envelope")
            return []
        }
        if let output = zlibInflate(payload, rawDeflate: true) {
            return output.map { NSNumber(value: $0) } as NSArray
        }
        if let output = inflateCandidate(payload) {
            return output.map { NSNumber(value: $0) } as NSArray
        }
        var capacity = max(1024, payload.count * 4)
        for _ in 0..<10 {
            var output = Array(repeating: UInt8(0), count: capacity)
            let decoded = payload.withUnsafeBytes { source in
                output.withUnsafeMutableBytes { destination in
                    compression_decode_buffer(
                        destination.bindMemory(to: UInt8.self).baseAddress!,
                        capacity,
                        source.bindMemory(to: UInt8.self).baseAddress!,
                        payload.count,
                        nil,
                        COMPRESSION_ZLIB
                    )
                }
            }
            if decoded > 0 {
                output.removeLast(output.count - decoded)
                return output.map { NSNumber(value: $0) } as NSArray
            }
            capacity *= 2
        }
        executionContext.log("GZIPInputStream failed to decode payload")
        return []
    }


    private func gzipPayload(_ input: [UInt8]) -> [UInt8]? {
        guard input.count >= 18, input[0] == 0x1f, input[1] == 0x8b, input[2] == 8 else { return nil }
        let flags = input[3]
        // Reserved bits must be clear per RFC 1952.
        guard flags & 0xe0 == 0 else { return nil }
        var index = 10
        let trailerStart = input.count - 8

        if flags & 0x04 != 0 {
            guard index + 2 <= trailerStart else { return nil }
            let length = Int(input[index]) | (Int(input[index + 1]) << 8)
            index += 2
            guard index + length <= trailerStart else { return nil }
            index += length
        }
        if flags & 0x08 != 0 {
            guard skipZeroTerminatedField(input, index: &index, limit: trailerStart) else { return nil }
        }
        if flags & 0x10 != 0 {
            guard skipZeroTerminatedField(input, index: &index, limit: trailerStart) else { return nil }
        }
        if flags & 0x02 != 0 {
            guard index + 2 <= trailerStart else { return nil }
            index += 2
        }
        guard index < trailerStart else { return nil }
        return Array(input[index..<trailerStart])
    }

    private func skipZeroTerminatedField(_ input: [UInt8], index: inout Int, limit: Int) -> Bool {
        while index < limit {
            defer { index += 1 }
            if input[index] == 0 { return true }
        }
        return false
    }

    private func zlibInflate(_ input: [UInt8], rawDeflate: Bool) -> [UInt8]? {
        guard !input.isEmpty else { return nil }
        var outputPointer: UnsafeMutablePointer<UInt8>?
        var outputLength = 0
        let status = input.withUnsafeBytes { buffer -> Int32 in
            guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else { return -1 }
            return sourceread_zlib_inflate(
                base,
                input.count,
                &outputPointer,
                &outputLength,
                rawDeflate ? 1 : 0
            )
        }
        guard status == 0, let outputPointer, outputLength > 0 else {
            if let outputPointer { sourceread_zlib_free(outputPointer) }
            return nil
        }
        defer { sourceread_zlib_free(outputPointer) }
        return Array(UnsafeBufferPointer(start: outputPointer, count: outputLength))
    }

    private func inflateCandidate(_ candidate: [UInt8]) -> [UInt8]? {
        guard !candidate.isEmpty else { return nil }

        // The SDK imports compression_stream with non-optional source and
        // destination pointers. Seed them with one-byte allocations, then
        // replace both pointers with the actual buffers before processing.
        let seedDestination = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        let seedSource = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        var stream = compression_stream(
            dst_ptr: seedDestination,
            dst_size: 0,
            src_ptr: UnsafePointer(seedSource),
            src_size: 0,
            state: nil
        )
        seedDestination.deallocate()
        seedSource.deallocate()

        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            return nil
        }
        defer { compression_stream_destroy(&stream) }

        var output: [UInt8] = []
        var destination = Array(repeating: UInt8(0), count: max(4096, candidate.count * 4))
        return candidate.withUnsafeBytes { sourceBuffer -> [UInt8]? in
            guard let sourcePointer = sourceBuffer.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.src_ptr = sourcePointer
            stream.src_size = candidate.count

            for _ in 0..<4096 {
                let status = destination.withUnsafeMutableBytes { destinationBuffer -> compression_status in
                    stream.dst_ptr = destinationBuffer.bindMemory(to: UInt8.self).baseAddress!
                    stream.dst_size = destinationBuffer.count
                    return compression_stream_process(&stream, 1)
                }
                let produced = destination.count - stream.dst_size
                if produced > 0 {
                    output.append(contentsOf: destination[0..<produced])
                }
                if status == COMPRESSION_STATUS_END { return output }
                if status == COMPRESSION_STATUS_ERROR { return nil }
                if stream.src_size == 0 && produced == 0 { return nil }
            }
            return nil
        }
    }

    // MARK: - Files and ZIP

    func readFile(_ path: String) -> NSArray {
        guard let url = resolvedURL(path), let data = try? Data(contentsOf: url) else { return [] }
        return data.map { NSNumber(value: $0) } as NSArray
    }

    func readText(_ path: String, charset: String? = nil) -> String {
        guard let url = resolvedURL(path), let data = try? Data(contentsOf: url) else { return "" }
        return decodeText(data, charset: charset)
    }

    /// Legado's cacheFile is a small persistent file cache, not just an in-memory
    /// variable. Keep it inside the per-app sandbox so sources can share helper
    /// data without escaping the application container.
    @discardableResult
    func cacheFile(_ path: String, content: Any?) -> AnyObject {
        guard let url = resolvedURL(path, createParent: true) else { return NSString(string: "") }
        do {
            let data = data(from: content)
            try data.write(to: url, options: .atomic)
            // Preserve Legado's return shape: text callers receive their text,
            // while byte-array callers keep an array instead of a JSON string.
            if let text = content as? String { return text as NSString }
            if let values = content as? NSArray { return values }
            return NSString(string: RuleExecutionContext.bridgeString(content))
        } catch {
            executionContext.log("cacheFile failed: \(error.localizedDescription)")
            return NSString(string: "")
        }
    }

    /// Alias used by newer Android sources.  Both write paths share the same
    /// sandbox and byte conversion rules so binary helper files round-trip.
    @discardableResult
    func writeFile(_ path: String, content: Any?) -> Bool {
        guard let url = resolvedURL(path, createParent: true) else { return false }
        do {
            try data(from: content).write(to: url, options: .atomic)
            return true
        } catch {
            executionContext.log("writeFile failed: \(error.localizedDescription)")
            return false
        }
    }

    func fileExists(_ path: String) -> Bool {
        guard let url = resolvedURL(path) else { return false }
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return false }
        return !isDirectory.boolValue
    }

    /// Metadata facade for Android-style `java.getFile(path)` helpers.  Keep
    /// the complete shape in one native call so repeated `exists()/length()`
    /// checks do not each cross the JavaScriptCore bridge.
    func fileInfo(_ path: String) -> NSDictionary {
        guard let url = resolvedURL(path) else {
            return [
                "path": path,
                "absolutePath": "",
                "name": "",
                "parent": "",
                "exists": false,
                "isFile": false,
                "isDirectory": false,
                "length": 0
            ] as NSDictionary
        }
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        let isDirectory = resourceValues?.isDirectory ?? false
        let exists = fileManager.fileExists(atPath: url.path)
        let attributes = exists ? (try? fileManager.attributesOfItem(atPath: url.path)) : nil
        let length = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)
            .map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        return [
            "path": url.path,
            "absolutePath": url.path,
            "name": url.lastPathComponent,
            "parent": url.deletingLastPathComponent().path,
            "exists": exists,
            "isFile": exists && !isDirectory,
            "isDirectory": exists && isDirectory,
            "length": length,
            "lastModified": modified,
            "canRead": exists && fileManager.isReadableFile(atPath: url.path),
            "canWrite": exists && fileManager.isWritableFile(atPath: url.path)
        ] as NSDictionary
    }

    func listFiles(_ path: String) -> NSArray {
        guard let url = resolvedURL(path), fileManager.fileExists(atPath: url.path) else {
            return [] as NSArray
        }
        let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
        guard resourceValues?.isDirectory == true,
              let values = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return [] as NSArray
        }
        return values.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(\.path) as NSArray
    }

    @discardableResult
    func makeDirectory(_ path: String) -> Bool {
        guard let url = resolvedURL(path, createParent: true) else { return false }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            return true
        } catch {
            executionContext.log("mkdirs failed: \(error.localizedDescription)")
            return false
        }
    }

    @discardableResult
    func deleteFile(_ path: String) -> Bool {
        guard let url = resolvedURL(path) else { return false }
        do {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
            return true
        } catch {
            executionContext.log("deleteFile failed: \(error.localizedDescription)")
            return false
        }
    }

    func downloadFile(_ rawURL: String, path: String) -> String {
        guard let sourceURL = URL(string: rawURL), let destination = resolvedURL(path, createParent: true) else { return "" }
        let semaphore = DispatchSemaphore(value: 0)
        var output = ""
        URLSession.shared.dataTask(with: sourceURL) { data, _, error in
            defer { semaphore.signal() }
            guard error == nil, let data else { return }
            do {
                try data.write(to: destination, options: .atomic)
                output = destination.path
            } catch {
                self.executionContext.log("downloadFile failed: \(error.localizedDescription)")
            }
        }.resume()
        _ = semaphore.wait(timeout: .now() + 30)
        return output
    }

    func unzipFile(_ path: String) -> String {
        guard let archiveURL = resolvedURL(path) else { return "" }
        let destination = archiveURL.deletingPathExtension()
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try fileManager.unzipItem(at: archiveURL, to: destination)
            return destination.path
        } catch {
            executionContext.log("unzipFile failed: \(error.localizedDescription)")
            return ""
        }
    }

    func textFiles(in path: String) -> NSArray {
        guard let folder = resolvedURL(path),
              let enumerator = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        let values = enumerator.compactMap { item -> String? in
            guard let url = item as? URL,
                  ["txt", "text", "html", "htm"].contains(url.pathExtension.lowercased()) else { return nil }
            return url.path
        }.sorted()
        return values as NSArray
    }

    func zipData(zipPath: String, entryName: String) -> Data? {
        guard let url = resolvedURL(zipPath), let archive = Archive(url: url, accessMode: .read),
              let entry = archive[entryName] else { return nil }
        var data = Data()
        do {
            _ = try archive.extract(entry) { data.append($0) }
            return data
        } catch {
            executionContext.log("ZIP read failed: \(error.localizedDescription)")
            return nil
        }
    }

    func zipString(zipPath: String, entryName: String, charset: String?) -> String {
        guard let data = zipData(zipPath: zipPath, entryName: entryName) else { return "" }
        return decodeText(data, charset: charset)
    }

    private func resolvedURL(_ path: String, createParent: Bool = false) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let candidate: URL
        if trimmed.hasPrefix("file://"), let url = URL(string: trimmed) {
            candidate = url
        } else if (trimmed as NSString).isAbsolutePath {
            candidate = URL(fileURLWithPath: trimmed)
        } else {
            candidate = sandboxURL.appendingPathComponent(trimmed)
        }
        let standardized = candidate.standardizedFileURL
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        guard standardized.path == home || standardized.path.hasPrefix(home + "/") else { return nil }
        if createParent {
            try? fileManager.createDirectory(at: standardized.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return standardized
    }

    private func bytes(from value: Any?) -> [UInt8] {
        if let jsValue = value as? JSValue {
            if jsValue.isArray {
                // Avoid JSValue.toArray() for binary inputs.  On older
                // JavaScriptCore versions it may deep-bridge an injected
                // NSArray as an empty Swift array.  Indexed access keeps the
                // original JS values intact and also handles nested arrays.
                let length = max(
                    0,
                    max(
                        Int(jsValue.forProperty("length")?.toInt32() ?? 0),
                        Int(jsValue.forProperty("count")?.toInt32() ?? 0)
                    )
                )
                if length == 0, let object = jsValue.toObject() as? NSArray, object.count > 0 {
                    return bytes(from: object)
                }
                var output: [UInt8] = []
                output.reserveCapacity(length)
                for index in 0..<length {
                    let item = jsValue.atIndex(index)
                    if let item, item.isNumber {
                        output.append(item.toNumber().uint8Value)
                    } else if let item, item.isString {
                        output.append(contentsOf: Array(item.toString().utf8))
                    } else {
                        output.append(contentsOf: bytes(from: item))
                    }
                }
                return output
            }
            if jsValue.isNumber { return [jsValue.toNumber().uint8Value] }
            if jsValue.isString {
                return Array(jsValue.toString().utf8)
            }
            if let object = jsValue.toObject() {
                return bytes(from: object)
            }
        }
        if let data = value as? Data { return Array(data) }
        if let values = value as? [UInt8] { return values }
        if let values = value as? [Int] { return values.map { UInt8(clamping: $0) } }
        if let values = value as? [NSNumber] { return values.map(\.uint8Value) }
        if let values = value as? [Any] {
            return values.compactMap {
                if let number = $0 as? NSNumber { return number.uint8Value }
                if let number = $0 as? Int { return UInt8(clamping: number) }
                if let number = $0 as? UInt8 { return number }
                return nil
            }
        }
        if let values = value as? NSArray {
            return values.compactMap {
                if let number = $0 as? NSNumber { return number.uint8Value }
                if let number = $0 as? Int { return UInt8(clamping: number) }
                if let number = $0 as? UInt8 { return number }
                if let jsValue = $0 as? JSValue, jsValue.isNumber { return jsValue.toNumber().uint8Value }
                return nil
            }
        }
        return Array(RuleExecutionContext.bridgeString(value).utf8)
    }

    private func commonCrypto(
        payload: [UInt8],
        key: [UInt8],
        iv: [UInt8],
        algorithm: CCAlgorithm,
        mode: String,
        padding: String,
        decrypt: Bool
    ) throws -> [UInt8] {
        let blockSize = algorithm == CCAlgorithm(kCCAlgorithm3DES) ? kCCBlockSize3DES : kCCBlockSizeDES
        let keyLength = algorithm == CCAlgorithm(kCCAlgorithm3DES) ? kCCKeySize3DES : kCCKeySizeDES
        var normalizedKeyBytes = Array((key + Array(repeating: 0, count: keyLength)).prefix(keyLength))
        if algorithm == CCAlgorithm(kCCAlgorithm3DES), key.count == 16 {
            normalizedKeyBytes = key + Array(key.prefix(8))
        }
        var input = payload
        if !decrypt && padding == "ZeroPadding" {
            let count = (blockSize - (input.count % blockSize)) % blockSize
            if count > 0 { input += Array(repeating: 0, count: count) }
        }
        var options: CCOptions = 0
        if mode == "ECB" { options |= CCOptions(kCCOptionECBMode) }
        if padding == "PKCS7" { options |= CCOptions(kCCOptionPKCS7Padding) }
        let keyData = Data(normalizedKeyBytes)
        let inputData = Data(input)
        let ivData = Data((iv + Array(repeating: 0, count: blockSize)).prefix(blockSize))
        var output = Array(repeating: UInt8(0), count: input.count + blockSize)
        var moved = 0
        let status: CCCryptorStatus = keyData.withUnsafeBytes { keyBuffer in
            inputData.withUnsafeBytes { inputBuffer in
                ivData.withUnsafeBytes { ivBuffer in
                    output.withUnsafeMutableBytes { outputBuffer in
                        CCCrypt(
                            decrypt ? CCOperation(kCCDecrypt) : CCOperation(kCCEncrypt),
                            algorithm,
                            options,
                            keyBuffer.baseAddress,
                            keyData.count,
                            mode == "ECB" ? nil : ivBuffer.baseAddress,
                            inputBuffer.baseAddress,
                            inputData.count,
                            outputBuffer.baseAddress,
                            outputBuffer.count,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw NSError(domain: "CommonCrypto", code: Int(status)) }
        output.removeLast(output.count - moved)
        if decrypt && padding == "ZeroPadding" {
            while output.last == 0 { output.removeLast() }
        }
        return output
    }

    private func normalizedKey(_ value: [UInt8]) -> [UInt8] {
        let size = value.count <= 16 ? 16 : (value.count <= 24 ? 24 : 32)
        return Array((value + Array(repeating: 0, count: size)).prefix(size))
    }

    private func normalizedIV(_ value: [UInt8]) -> [UInt8] {
        Array((value + Array(repeating: 0, count: 16)).prefix(16))
    }

    private static func normalizedBase64(_ value: String) -> String {
        var text = value
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = text.count % 4
        if remainder != 0 { text += String(repeating: "=", count: 4 - remainder) }
        return text
    }

    private static func paddedBase64(_ value: String) -> String {
        let remainder = value.count % 4
        return remainder == 0 ? value : value + String(repeating: "=", count: 4 - remainder)
    }

    private static let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )

}
