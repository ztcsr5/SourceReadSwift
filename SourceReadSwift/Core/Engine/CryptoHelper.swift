import Foundation
import CommonCrypto

public struct CryptoHelper {
    public static func aesDecrypt(data: Data, key: Data, iv: Data) -> Data? {
        let keyLength = key.count
        guard keyLength == kCCKeySizeAES128 || keyLength == kCCKeySizeAES192 || keyLength == kCCKeySizeAES256 else {
            return nil
        }
        guard iv.count == kCCBlockSizeAES128 else { return nil }

        let bufferSize = data.count + kCCBlockSizeAES128
        var buffer = Data(count: bufferSize)
        var numBytesDecrypted: size_t = 0

        let status = buffer.withUnsafeMutableBytes { bufferPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress,
                            keyLength,
                            ivPtr.baseAddress,
                            dataPtr.baseAddress,
                            data.count,
                            bufferPtr.baseAddress,
                            bufferSize,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { return nil }
        buffer.count = numBytesDecrypted
        return buffer
    }

    public static func aesDecryptBase64(base64: String, keyText: String, ivText: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let key = keyText.data(using: .utf8),
              let iv = ivText.data(using: .utf8) else { return nil }
        guard let decrypted = aesDecrypt(data: data, key: key, iv: iv) else { return nil }
        return String(data: decrypted, encoding: .utf8)
    }
}
