import Foundation
import XCTest
@testable import SourceReadSwift

/// Stage 25 compatibility probes.  The tests deliberately stay offline and
/// exercise the same JSCore/Legado bridge used by the source engine.
final class LegadoStage25CompatibilityTests: XCTestCase {
    func testQueryTTFParsesCmapLocaAndSimpleGlyph() throws {
        let font = QueryTTF(data: makeMinimalTTF())

        XCTAssertEqual(font.getGlyfIdByUnicode(65), 1)
        XCTAssertEqual(font.getGlyfByUnicode(65), "10,20")
        XCTAssertEqual(font.getUnicodeByGlyf("10,20"), 65)
        XCTAssertEqual(font.getGlyfIdByUnicode(66), 0)
        XCTAssertTrue(font.isBlankUnicode(0x20))
        XCTAssertFalse(font.isBlankUnicode(65))

        let format4 = QueryTTF(data: makeMinimalTTF(cmap: makeCmap4Table()))
        XCTAssertEqual(format4.getGlyfIdByUnicode(65), 1)
        XCTAssertEqual(format4.getGlyfByUnicode(65), "10,20")

        let deltaFont = QueryTTF(data: makeMinimalTTF(
            loca: makeTwoPointLocaTable(),
            glyf: makeTwoPointGlyfTable()
        ))
        XCTAssertEqual(deltaFont.getGlyfByUnicode(65), "10,20|-5,-3")
    }

    func testQueryTTFJavaScriptBridgeSupportsBase64AndHTTPBytes() throws {
        let base64 = makeMinimalTTF().base64EncodedString()
        let context = RuleExecutionContext(responseHandler: { encoded in
            guard encoded.contains("font.fixture") else { return nil }
            let data = makeMinimalTTF()
            return SourceResponse(
                url: URL(string: "https://font.fixture/final.ttf")!,
                statusCode: 200,
                headers: ["Content-Type": "font/ttf"],
                body: "",
                data: data
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate(
            """
            var local = java.queryTTF(font);
            var remote = java.queryTTF('https://font.fixture/font.ttf');
            JSON.stringify({
              local: [local.getGlyfIdByUnicode(65), local.getGlyfByUnicode(65), local.getUnicodeByGlyf('10,20'), local.isBlankUnicode(32)],
              remote: [remote.getGlyfIdByUnicode(65), remote.handle.indexOf('ttf-') === 0]
            })
            """,
            variables: ["font": base64]
        )
        let object = try jsonObject(result)
        XCTAssertEqual(object["local"] as? [AnyHashable], [1, "10,20", 65, true])
        XCTAssertEqual(object["remote"] as? [AnyHashable], [1, true])
    }

    func testCreateSignSupportsStatefulBase64HexAndByteArrayVerification() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate(
            """
            var signer = java.createSign('SHA256withRSA').initSign(privateKey).update('hello');
            var signature = signer.signBase64();
            var hex = signer.signHex();
            var verifier = java.createSign('SHA256withRSA').initVerify(publicKey).update('hello');
            var bytes = java.strToBytes('hello');
            var byteVerifier = java.createSign('SHA256withRSA').initVerify(publicKey).update(bytes);
            JSON.stringify({
              signed: signature.length > 0,
              base64Valid: verifier.verifyBase64(signature),
              hexValid: verifier.verifyHex(hex),
              bytesValid: byteVerifier.verify(signature),
              badMessage: java.createSign('SHA256withRSA').initVerify(publicKey).update('wrong').verify(signature)
            })
            """,
            variables: ["privateKey": Self.privateKeyPEM, "publicKey": Self.publicKeyPEM]
        )
        let object = try jsonObject(result)
        XCTAssertEqual(object["signed"] as? Bool, true)
        XCTAssertEqual(object["base64Valid"] as? Bool, true)
        XCTAssertEqual(object["hexValid"] as? Bool, true)
        XCTAssertEqual(object["bytesValid"] as? Bool, true)
        XCTAssertEqual(object["badMessage"] as? Bool, false)
    }

    func testAsymmetricCryptoEncryptsAndDecryptsWithRSA() throws {
        let runtime = JSCoreRuntime()
        let result = runtime.evaluate(
            """
            var encrypted = java.createAsymmetricCrypto('RSA/ECB/PKCS1Padding')
              .setPublicKey(publicKey).encryptBase64('hello');
            var clear = java.createAsymmetricCrypto('RSA/ECB/PKCS1Padding')
              .setPrivateKey(privateKey).decryptBase64(encrypted);
            [encrypted.length > 0, clear].join('|')
            """,
            variables: ["privateKey": Self.privateKeyPEM, "publicKey": Self.publicKeyPEM]
        )
        guard case .success(let value) = result else {
            return XCTFail("expected RSA round trip: \(result)")
        }
        XCTAssertEqual(value, "true|hello")
    }

    func testVerificationCodeUsesCachedValueAndArchivesFailExplicitly() throws {
        let context = RuleExecutionContext()
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate(
            """
            java.put('captcha:https://fixture.local/captcha.png', '42');
            JSON.stringify([
              java.getVerificationCode('https://fixture.local/captcha.png'),
              java.getVerificationCode('https://fixture.local/missing.png'),
              java.un7zFile('fixture.7z'),
              java.unrarFile('fixture.rar')
            ])
            """
        )
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let values = try JSONSerialization.jsonObject(with: data) as? [String] else {
            return XCTFail("expected verification/archive values: \(result)")
        }
        XCTAssertEqual(values, ["42", "", "", ""])
        XCTAssertTrue(context.logs().contains { $0.contains("verification-required") })
        XCTAssertTrue(context.logs().contains { $0.contains("java.un7zFile") && $0.contains("unsupported") })
        XCTAssertTrue(context.logs().contains { $0.contains("java.unrarFile") && $0.contains("unsupported") })
    }

    func testSearchDetailTocContentPreservesStateAndBodyJsAcrossStages() async throws {
        let source = BookSource(
            bookSourceName: "Stage 25 pipeline",
            bookSourceUrl: "https://fixture.local/",
            searchUrl: "https://fixture.local/search?q={{key}}",
            ruleSearch: SourceRule(fields: [
                "bookList": "$.books",
                "name": "$.name",
                "author": "$.author",
                "bookUrl": "$.url",
                "bodyJs": "java.put('token', 'search'); return result"
            ]),
            ruleBookInfo: SourceRule(fields: [
                "name": "$.name",
                "author": "$.author",
                "tocUrl": "$.toc",
                "bodyJs": "java.put('token', 'detail'); return result"
            ]),
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters",
                "chapterName": "$.title",
                "chapterUrl": "$.url",
                "bodyJs": "java.put('token', 'toc'); return result"
            ]),
            ruleContent: SourceRule(fields: [
                "content": "$.content",
                "bodyJs": "java.put('token', 'content'); return result.replace('ENCODED', '正文')"
            ]),
            header: #"{"X-Stage":"{{token}}"}"#
        )
        let network = Stage25PipelineNetwork()
        let engine = LegadoSourceEngine(network: network)

        let books = try unwrap(await engine.searchBooks(source: source, keyword: "swift", page: 1))
        let detail = try unwrap(await engine.getBookDetail(source: source, book: try XCTUnwrap(books.first)))
        let chapters = try unwrap(await engine.getChapterList(source: source, book: detail))
        let content = try unwrap(await engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))

        XCTAssertEqual(books.first?.name, "Stage 25")
        XCTAssertEqual(detail.tocUrl, "https://fixture.local/toc/1")
        XCTAssertEqual(chapters.first?.url, "https://fixture.local/chapter/1")
        XCTAssertEqual(content.paragraphs, ["正文"])
        XCTAssertEqual(network.stageHeaders, ["", "search", "detail", "toc"])
    }

    func testAjaxAllFetchResponseBytesAndJSONPathJsoupMix() throws {
        let context = RuleExecutionContext(responseHandler: { encoded in
            let isPost = encoded.contains("\"method\":\"POST\"")
            let isOne = encoded.contains("/one")
            let body = isPost ? #"{"kind":"post"}"# : (isOne ? #"{"kind":"one"}"# : #"{"kind":"two"}"#)
            return SourceResponse(
                url: URL(string: isPost ? "https://fixture.local/post-final" : (isOne ? "https://fixture.local/one-final" : "https://fixture.local/two-final"))!,
                statusCode: isPost ? 201 : (isOne ? 206 : 204),
                headers: ["X-Trace": isPost ? "post" : "fixture", "Content-Type": "application/json"],
                body: body,
                data: Data(body.utf8)
            )
        })
        let runtime = JSCoreRuntime(executionContext: context)
        let result = runtime.evaluate(
            """
            var all = java.ajaxAll(['https://fixture.local/one', 'https://fixture.local/two']);
            var post = fetch('https://fixture.local/post', {method:'POST', body:'q=1'});
            var jsonNames = java.getStringList('{"items":[{"name":"A"},{"name":"B"}]}', '$.items[*].name');
            var doc = org.jsoup.Jsoup.parse('<ul><li>One</li><li>Two</li></ul>');
            JSON.stringify({
              statuses: [all.get(0).status, all.get(1).status],
              urls: [all.get(0).finalUrl(), all.get(1).finalUrl()],
              header: all.get(0).headers.get('x-trace'),
              bytes: all.get(0).body().bytes().length,
              post: post.json().kind,
              names: jsonNames,
              dom: doc.select('li').last().text()
            })
            """
        )
        let object = try jsonObject(result)
        XCTAssertEqual(object["statuses"] as? [Int], [206, 204])
        XCTAssertEqual(object["urls"] as? [String], ["https://fixture.local/one-final", "https://fixture.local/two-final"])
        XCTAssertEqual(object["header"] as? String, "fixture")
        XCTAssertEqual(object["bytes"] as? Int, 14)
        XCTAssertEqual(object["post"] as? String, "post")
        XCTAssertEqual(object["names"] as? [String], ["A", "B"])
        XCTAssertEqual(object["dom"] as? String, "Two")
    }

    private func jsonObject(_ result: Result<String, SourceEngineError>) throws -> [String: Any] {
        guard case .success(let value) = result,
              let data = value.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("expected JSON result: \(result)")
            throw NSError(domain: "Stage25Tests", code: 1)
        }
        return object
    }

    private func unwrap<T>(_ result: Result<T, SourceEngineError>) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("pipeline failed: \(error)")
            throw error
        }
    }

    private static let privateKeyPEM = """
    -----BEGIN PRIVATE KEY-----
    MIICeAIBADANBgkqhkiG9w0BAQEFAASCAmIwggJeAgEAAoGBALnFj4hOjhcM6eI/
    ODBEoOiWF+ySoNfAtyhmPMF+8Rtxx3lyD8G7V8o/Ctq7J+OWurmDigMedWZVUltB
    6oUGpIr5HiEUpV1aXqAxnBdGHv7VrBDqOunxmn8shSFvWVSsyV7ptXkGTL1dL7SE
    tt7Cor6/372axWCLnJy2GK4cXblHAgMBAAECgYBX9H7JpY/GwBl4QkBjMgsRNAct
    vhqjLB5L5WP8pRKY0N0F1gg5zG57Vi/YceYn7jSIIwxT/7bL9behd2sHAqciSqDc
    QfpYf3XkVPHee/Cuzj+sI3wYELVFxmgTkk5LJOJFCmlDCXEkYgED2K6JLqKz67Yw
    EZQbAQ4Akhv6hXGdQQJBAOUj4GEgEWmaxdIKHRXn/afyMo1cwISft2qiEly4umcn
    oUUh3wjxalHNbRt9K2rOMg2Hy4kftp6XO1C7r8YdA2ECQQDPjESwAEW6xYV0L6mi
    LwuMxB7e9RXCLZtQvjAx2ySz/kb9MOg9CAv9xH4H5JU2HsxR5WZLIlR3qwR6yO12
    I6WnAkEAuiRd56i8XHSt1QYAQMZ4KhG3fVzmzBZPUuGcVxR94MSx3s44ODSdsRxX
    UShqt9YPlSxGbPuFR+oE9n2xuhfhoQJBAKIKMopy+/3xPttSZw9vyYWyjSOnl8BN
    2Sg2BOy32rUIvqXo7DjSMoKDSZ6h8XkanI0IHFBm0inIBKxUeUk2VZsCQQCzXPsl
    IglJUo/IqMd7AqZtQB5jwGP0N47m8alVw+oPWLB3Wpgs02/GX62dyAR0t0CJJT0c
    uya0VofNLz9W3zO9
    -----END PRIVATE KEY-----
    """

    private static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQC5xY+ITo4XDOniPzgwRKDolhfs
    kqDXwLcoZjzBfvEbccd5cg/Bu1fKPwrauyfjlrq5g4oDHnVmVVJbQeqFBqSK+R4h
    FKVdWl6gMZwXRh7+1awQ6jrp8Zp/LIUhb1lUrMle6bV5Bky9XS+0hLbewqK+v9+9
    msVgi5ycthiuHF25RwIDAQAB
    -----END PUBLIC KEY-----
    """
}

private final class Stage25PipelineNetwork: SourceNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var stageHeaders: [String] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let path = request.url.path
        let stage = request.headers.first { $0.key.caseInsensitiveCompare("X-Stage") == .orderedSame }?.value ?? ""
        lock.lock(); stageHeaders.append(stage); lock.unlock()
        switch path {
        case "/search":
            return .success(response(request, #"{"books":[{"name":"Stage 25","author":"Fixture","url":"/book/1"}]}"#))
        case "/book/1":
            guard stage == "search" else { return .failure(.network("detail stage token mismatch")) }
            return .success(response(request, #"{"name":"Stage 25","author":"Fixture","toc":"/toc/1"}"#))
        case "/toc/1":
            guard stage == "detail" else { return .failure(.network("toc stage token mismatch")) }
            return .success(response(request, #"{"chapters":[{"title":"第一章","url":"/chapter/1"}]}"#))
        case "/chapter/1":
            guard stage == "toc" else { return .failure(.network("content stage token mismatch")) }
            return .success(response(request, #"{"content":"ENCODED"}"#))
        default:
            return .failure(.network("unknown stage URL"))
        }
    }

    private func response(_ request: SourceRequest, _ body: String) -> SourceResponse {
        SourceResponse(url: request.url, statusCode: 200, headers: ["Content-Type": "application/json"], body: body, data: Data(body.utf8))
    }
}

private func makeMinimalTTF(
    cmap: [UInt8] = makeCmapTable(),
    loca: [UInt8] = makeLocaTable(),
    glyf: [UInt8] = makeGlyfTable()
) -> Data {
    var file = Array(repeating: UInt8(0), count: 12 + 5 * 16)
    var tables: [(String, [UInt8])] = [
        ("head", makeHeadTable()),
        ("maxp", makeMaxpTable()),
        ("cmap", cmap),
        ("loca", loca),
        ("glyf", glyf)
    ]
    var offsets: [(Int, Int)] = []
    for (_, table) in tables {
        while file.count % 4 != 0 { file.append(0) }
        let offset = file.count
        file.append(contentsOf: table)
        offsets.append((offset, table.count))
    }
    putU32(&file, at: 0, value: 0x00010000)
    putU16(&file, at: 4, value: 5)
    for (index, item) in tables.enumerated() {
        let base = 12 + index * 16
        file.replaceSubrange(base..<(base + 4), with: Array(item.0.utf8))
        putU32(&file, at: base + 4, value: 0)
        putU32(&file, at: base + 8, value: UInt32(offsets[index].0))
        putU32(&file, at: base + 12, value: UInt32(offsets[index].1))
    }
    return Data(file)
}

private func makeHeadTable() -> [UInt8] {
    var table = Array(repeating: UInt8(0), count: 54)
    putU16(&table, at: 18, value: 1000)
    putU16(&table, at: 50, value: 0)
    return table
}

private func makeMaxpTable() -> [UInt8] {
    var table: [UInt8] = []
    appendU32(&table, 0x00010000)
    appendU16(&table, 2)
    return table
}

private func makeCmapTable() -> [UInt8] {
    var table: [UInt8] = []
    appendU16(&table, 0)
    appendU16(&table, 1)
    appendU16(&table, 3)
    appendU16(&table, 1)
    appendU32(&table, 12)
    appendU16(&table, 6)
    appendU16(&table, 12)
    appendU16(&table, 0)
    appendU16(&table, 65)
    appendU16(&table, 1)
    appendU16(&table, 1)
    return table
}

private func makeCmap4Table() -> [UInt8] {
    var table: [UInt8] = []
    appendU16(&table, 0)       // cmap version
    appendU16(&table, 1)       // encoding records
    appendU16(&table, 3)       // Windows
    appendU16(&table, 1)       // Unicode BMP
    appendU32(&table, 12)      // subtable offset
    appendU16(&table, 4)       // format
    appendU16(&table, 32)      // length
    appendU16(&table, 0)       // language
    appendU16(&table, 4)       // segCountX2 (two segments)
    appendU16(&table, 0); appendU16(&table, 0); appendU16(&table, 0)
    appendU16(&table, 65); appendU16(&table, 0xffff)
    appendU16(&table, 0)
    appendU16(&table, 65); appendU16(&table, 0xffff)
    appendI16(&table, -64); appendI16(&table, 1)
    appendU16(&table, 0); appendU16(&table, 0)
    return table
}

private func makeLocaTable() -> [UInt8] {
    var table: [UInt8] = []
    appendU16(&table, 0)
    appendU16(&table, 0)
    appendU16(&table, 9)
    return table
}

private func makeGlyfTable() -> [UInt8] {
    var table: [UInt8] = []
    appendI16(&table, 1)
    appendI16(&table, 0); appendI16(&table, 0)
    appendI16(&table, 10); appendI16(&table, 20)
    appendU16(&table, 0)
    appendU16(&table, 0)
    table.append(0x37)
    table.append(10)
    table.append(20)
    table.append(0)
    return table
}

private func makeTwoPointLocaTable() -> [UInt8] {
    var table: [UInt8] = []
    appendU16(&table, 0)
    appendU16(&table, 0)
    appendU16(&table, 10)
    return table
}

private func makeTwoPointGlyfTable() -> [UInt8] {
    var table: [UInt8] = []
    appendI16(&table, 1)
    appendI16(&table, -5); appendI16(&table, -3)
    appendI16(&table, 10); appendI16(&table, 20)
    appendU16(&table, 1)
    appendU16(&table, 0)
    table.append(0x37); table.append(0x07)
    table.append(10); table.append(5)
    table.append(20); table.append(3)
    return table
}

private func appendU16(_ bytes: inout [UInt8], _ value: Int) {
    bytes.append(UInt8((value >> 8) & 0xff)); bytes.append(UInt8(value & 0xff))
}

private func appendU32(_ bytes: inout [UInt8], _ value: Int) {
    bytes.append(UInt8((value >> 24) & 0xff)); bytes.append(UInt8((value >> 16) & 0xff))
    bytes.append(UInt8((value >> 8) & 0xff)); bytes.append(UInt8(value & 0xff))
}

private func appendI16(_ bytes: inout [UInt8], _ value: Int) {
    appendU16(&bytes, value < 0 ? value + 0x10000 : value)
}

private func putU16(_ bytes: inout [UInt8], at offset: Int, value: Int) {
    bytes[offset] = UInt8((value >> 8) & 0xff); bytes[offset + 1] = UInt8(value & 0xff)
}

private func putU32(_ bytes: inout [UInt8], at offset: Int, value: UInt32) {
    bytes[offset] = UInt8((value >> 24) & 0xff); bytes[offset + 1] = UInt8((value >> 16) & 0xff)
    bytes[offset + 2] = UInt8((value >> 8) & 0xff); bytes[offset + 3] = UInt8(value & 0xff)
}
