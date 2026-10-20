import XCTest
@testable import SourceReadSwift

/// Locks the Java/Legado charset bridge used by JSON book sources.
///
/// Android sources frequently pass GBK/GB18030/Big5 to `java.encodeURI`,
/// `URLEncoder`, `URLDecoder`, and `new java.lang.String(bytes, charset)`.
/// JavaScriptCore has no native GBK support, so these tests pin the
/// CoreFoundation-backed conversion and the percent-decoding semantics.
final class LegadoCharsetTests: XCTestCase {
    func testGBKRoundTripProducesExpectedBytes() throws {
        let data = try XCTUnwrap(LegadoCharset.encode("中文", charset: "GBK"))
        XCTAssertEqual([UInt8](data), [0xD6, 0xD0, 0xCE, 0xC4])
        XCTAssertEqual(LegadoCharset.decode(data, charset: "GBK"), "中文")
    }

    func testGBKFamilyAliasesShareTheSameEncoding() throws {
        let expected = try XCTUnwrap(LegadoCharset.encode("中文", charset: "GBK"))
        for alias in ["GB2312", "GB18030", "cp936", "EUC-CN", "windows-936"] {
            let data = try XCTUnwrap(LegadoCharset.encode("中文", charset: alias), alias)
            XCTAssertEqual([UInt8](data), [UInt8](expected), alias)
            XCTAssertEqual(LegadoCharset.decode(data, charset: alias), "中文", alias)
        }
    }

    func testBig5RoundTripProducesExpectedBytes() throws {
        let data = try XCTUnwrap(LegadoCharset.encode("中文", charset: "Big5"))
        XCTAssertEqual([UInt8](data), [0xA4, 0xA4, 0xA4, 0xE5])
        XCTAssertEqual(LegadoCharset.decode(data, charset: "Big5"), "中文")
        XCTAssertEqual(LegadoCharset.decode(data, charset: "cp950"), "中文")
    }

    func testPercentEncodeAndDecodeGBK() throws {
        XCTAssertEqual(
            LegadoCharset.percentEncode("中文", charset: "gbk"),
            "%D6%D0%CE%C4"
        )
        XCTAssertEqual(
            LegadoCharset.percentDecode("%D6%D0%CE%C4", charset: "gbk"),
            "中文"
        )
        // Literal characters outside the escapes must stay literal instead of
        // being re-encoded through the target charset.
        XCTAssertEqual(
            LegadoCharset.percentDecode("q=%D6%D0", charset: "gbk"),
            "q=中"
        )
        XCTAssertEqual(
            LegadoCharset.percentDecode("a+b", charset: "utf-8", plusAsSpace: true),
            "a b"
        )
    }

    func testJavaURLEncoderAndDecoderRespectGBK() throws {
        let result = JSCoreRuntime().evaluate("""
            var encoded = Packages.java.net.URLEncoder.encode('中文', 'GBK');
            var decoded = Packages.java.net.URLDecoder.decode(encoded, 'GBK');
            encoded + '|' + decoded;
        """)
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, "%D6%D0%CE%C4|中文")
    }

    func testJavaEncodeURIAndDecodeURIRespectBig5() throws {
        let result = JSCoreRuntime().evaluate("""
            var encoded = java.encodeURI('中文', 'Big5');
            var decoded = java.decodeURI(encoded, 'Big5');
            encoded + '|' + decoded;
        """)
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, "%A4%A4%A4%E5|中文")
    }

    func testJavaURIEncodeAliasesForwardCharset() throws {
        let result = JSCoreRuntime().evaluate("""
            var encoded = java.uriEncode('中文', 'gbk');
            var decoded = java.uriDecode(encoded, 'gbk');
            encoded + '|' + decoded;
        """)
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, "%D6%D0%CE%C4|中文")
    }

    func testJavaStringConstructorAndGetBytesUseGBK() throws {
        let result = JSCoreRuntime().evaluate("""
            var bytes = '中文'.getBytes('GBK');
            var restored = new Packages.java.lang.String(bytes, 'GBK');
            bytes.join(',') + '|' + restored.toString();
        """)
        guard case .success(let value) = result else {
            return XCTFail("expected success: \(result)")
        }
        XCTAssertEqual(value, "214,208,206,196|中文")
    }
}