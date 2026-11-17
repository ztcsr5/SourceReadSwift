import XCTest
@testable import SourceReadSwift

final class SourceAndroidBridgeCompatibilityTests: XCTestCase {
    func testCharsetForNameUsesExistingStringByteConversions() throws {
        let output = try JSCoreRuntime().evaluate("""
        var Charset = Packages.java.nio.charset.Charset;
        var utf8 = Charset.forName('uTf-8');
        var latin1 = Charset.forName('ISO-8859-1');
        var bytes = new Packages.java.lang.String('正文').getBytes(utf8);
        var restored = new Packages.java.lang.String(bytes, utf8);
        var binary = new Packages.java.lang.String([0, 127, -128, -1], latin1);
        var slice = new Packages.java.lang.String([0, 65, -1, 0], 1, 2, latin1);
        JSON.stringify([utf8.name(), String(latin1), bytes.join(','), String(restored),
          binary.getBytes(latin1).join(','), slice.getBytes(latin1).join(','),
          new Packages.java.lang.String('中文').getBytes(Charset.forName('GBK')).join(',')])
        """).get()
        let bytes = try XCTUnwrap(output.data(using: .utf8))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: bytes) as? [String], [
            "UTF-8", "ISO-8859-1", "230,173,163,230,150,135", "正文",
            "0,127,128,255", "65,255", "214,208,206,196"
        ])
    }

    func testCharsetForNameRejectsUnknownAndMalformedNames() throws {
        let output = try JSCoreRuntime().evaluate("""
        [null, '', ' utf-8', 'x-unknown-charset'].map(function(name) {
          try { Packages.java.nio.charset.Charset.forName(name); return 'accepted'; }
          catch (error) { return String(error.message); }
        }).join('|')
        """).get()
        XCTAssertEqual(output, "IllegalArgumentException|IllegalCharsetNameException|IllegalCharsetNameException|UnsupportedCharsetException")
    }

    func testHutoolMD5ReturnsBytesForAndroidBase64() throws {
        let result = JSCoreRuntime().evaluate("""
        var digest = Packages.cn.hutool.crypto.digest.DigestUtil.md5([0, 127, 128, 255, 13, 10]);
        var base64 = Packages.android.util.Base64;
        JSON.stringify({bytes: Array.from(digest), encoded: base64.encodeToString(digest, base64.NO_WRAP)})
        """)
        let output = try XCTUnwrap(try result.get().data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertEqual(object["bytes"] as? [Int], [92, 251, 68, 172, 200, 96, 201, 215, 194, 83, 29, 218, 210, 206, 54, 5])
        XCTAssertEqual(object["encoded"] as? String, "XPtErMhgydfCUx3a0s42BQ==")
    }

    func testHutoolMD5AcceptsEmptyAndSignedByteArrays() throws {
        let result = JSCoreRuntime().evaluate("""
        var digest = Packages.cn.hutool.crypto.digest.DigestUtil;
        var base64 = Packages.android.util.Base64;
        JSON.stringify([
          base64.encodeToString(digest.md5([]), base64.NO_WRAP),
          base64.encodeToString(digest.md5([0, 127, -128, -1, 13, 10]), base64.NO_WRAP),
          digest.md5Hex('abc')
        ])
        """)
        let output = try XCTUnwrap(try result.get().data(using: .utf8))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: output) as? [String], [
            "1B2M2Y8AsgTpgAmY7PhCfg==",
            "XPtErMhgydfCUx3a0s42BQ==",
            "900150983cd24fb0d6963f7d28e17f72"
        ])
    }

    func testStrResponseReplacesBodyWithoutChangingNetworkResponseCode() throws {
        var requests: [String] = []
        let runtime = JSCoreRuntime(ajaxHandler: { url in
            requests.append(url)
            return "encoded"
        })
        let result = runtime.evaluate("""
        var original = java.get('https://fixture.local/chapter');
        var response = Packages.io.legado.app.help.http.StrResponse(original.url(), 'decoded 正文');
        JSON.stringify({body: response.body(), url: response.url(), code: response.code(),
          message: response.message(), successful: response.isSuccessful(), error: response.errorBody(),
          headerCount: response.headers().size(), rawCode: response.raw().code(),
          originalCode: original.code, originalBody: String(original.body())})
        """)
        let output = try XCTUnwrap(try result.get().data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertEqual(object["body"] as? String, "decoded 正文")
        XCTAssertEqual(object["url"] as? String, "https://fixture.local/chapter")
        XCTAssertEqual(object["code"] as? Int, 200)
        XCTAssertEqual(object["message"] as? String, "OK")
        XCTAssertEqual(object["successful"] as? Bool, true)
        XCTAssertTrue(object["error"] is NSNull)
        XCTAssertEqual(object["headerCount"] as? Int, 0)
        XCTAssertEqual(object["rawCode"] as? Int, 200)
        XCTAssertEqual(object["originalCode"] as? Int, 200)
        XCTAssertEqual(object["originalBody"] as? String, "encoded")
        XCTAssertEqual(requests, ["https://fixture.local/chapter"])
    }

    func testStrResponseConstructorPreservesNullBodyAndInvalidURLFallback() throws {
        let result = JSCoreRuntime().evaluate("""
        var response = new Packages.io.legado.app.help.http.StrResponse('not an absolute URL', null);
        JSON.stringify({body: response.body(), url: response.url(), code: response.code()})
        """)
        let output = try XCTUnwrap(try result.get().data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertTrue(object["body"] is NSNull)
        XCTAssertEqual(object["url"] as? String, "http://localhost/")
        XCTAssertEqual(object["code"] as? Int, 200)
    }
}
