import XCTest
@testable import SourceReadSwift

/// Synthetic byte protocols exercise the APIs used by image rules without copying publisher rules or keys.
final class SourceImageByteCompatibilityTests: XCTestCase {
    private static let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII="

    func testSymmetricCryptoDecryptKeepsBinaryBytesInsteadOfDecodingUTF8() throws {
        let runtime = JSCoreRuntime()
        let output = try runtime.evaluate("""
        var expected = [137, 80, 78, 71, 0, 255, 128, 13, 10, 26, 10, 7];
        var key = '0123456789abcdef';
        var iv = 'fedcba9876543210';
        var encrypted = java.aesEncodeToByteArray(expected, key, 'AES/CBC/PKCS7Padding', iv);
        var decrypted = java.createSymmetricCrypto('AES/CBC/PKCS7Padding', key, iv).decrypt(encrypted);
        JSON.stringify({isArray: Array.isArray(decrypted), bytes: decrypted});
        """).get()
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        XCTAssertEqual(decoded["isArray"] as? Bool, true, "Image bytes cannot survive a UTF-8 String round trip")
        XCTAssertEqual(decoded["bytes"] as? [Int], [137, 80, 78, 71, 0, 255, 128, 13, 10, 26, 10, 7])
    }

    func testBufferConcatJoinsDecodedHeaderAndUntouchedImageTail() throws {
        let runtime = JSCoreRuntime()
        let output = try runtime.evaluate("""
        var header = new Uint8Array([137, 80, 78, 71]);
        var tail = [13, 10, 26, 10, 0, 255];
        JSON.stringify(Array.prototype.slice.call(Buffer.concat([header, tail])));
        """).get()
        let bytes = try JSONDecoder().decode([Int].self, from: Data(output.utf8))
        XCTAssertEqual(bytes, [137, 80, 78, 71, 13, 10, 26, 10, 0, 255])
    }

    func testJavaSignedByteImageOutputPreservesEveryByte() throws {
        let expected = try XCTUnwrap(Data(base64Encoded: Self.pngBase64))
        let runtime = JSCoreRuntime()
        let encoded = expected.map { Int($0 ^ 0x5A) }
        let output = try runtime.evaluate("""
        (function() {
            var stream = new Packages.java.io.ByteArrayInputStream(result);
            var decoded = new Packages.java.io.ByteArrayOutputStream();
            var next;
            while ((next = stream.read()) !== -1) decoded.write(next ^ 0x5A);
            return decoded.toByteArray().map(function(value) { return value > 127 ? value - 256 : value; });
        })();
        """, variables: ["result": encoded, "src": "https://fixture.invalid/image.bin"]).get()
        guard case .decoded(let image) = InlineImageDecoder.decode(output) else {
            return XCTFail("A Java byte[] containing negative octets must decode as the original image")
        }
        XCTAssertEqual(image.data, expected)
        XCTAssertEqual(image.fileExtension, "png")
    }

    func testSignedByteSupportDoesNotTruncateValuesOutsideAByte() {
        for invalid in [-129, 256] {
            let array = "[137,80,78,71,13,10,26,10,0,0,0,\(invalid)]"
            guard case .invalid = InlineImageDecoder.decode(array) else {
                return XCTFail("Out-of-range byte \(invalid) must remain invalid")
            }
        }
    }
}
