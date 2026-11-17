import CryptoKit
import Foundation
import XCTest
@testable import SourceReadSwift

final class PrivateCorpusHTTPTraceTests: XCTestCase {
    func testFormTraceDistinguishesMissingEmptyAndDuplicateFieldsWithoutValues() async throws {
        let trace = PrivateCorpusHTTPTrace(network: PrivateCorpusTraceFixtureNetwork())
        let request = SourceRequest(url: URL(string: "https://fixture.invalid/catalog")!, method: .post,
            headers: ["content-type": "application/x-www-form-urlencoded; charset=UTF-8"],
            body: Data("source=private-source&url=https%3A%2F%2Fprivate.invalid&name=&bookid=one&bookid=two&token=secret".utf8),
            expectedCharset: nil, timeout: 2)
        _ = await trace.load(request)
        let observations = await trace.snapshot()
        let shape = try XCTUnwrap(observations.first?.requestShape)
        XCTAssertEqual(shape.root, "form")
        XCTAssertEqual(shape.fieldCount, 6)
        XCTAssertEqual(shape.fields, ["source": "string", "url": "string", "name": "empty-string", "bookid": "duplicate"])
        XCTAssertNil(shape.fields["tab"])
        let encoded = String(decoding: try JSONEncoder().encode(shape), as: UTF8.self)
        for privateValue in ["private-source", "private.invalid", "one", "two", "token", "secret"] {
            XCTAssertFalse(encoded.contains(privateValue))
        }
    }

    func testFormInspectionUsesDeclaredTypeOrStrictKnownFieldShapeAndRespectsByteLimit() {
        let body = Data("bookid=fixture".utf8)
        let inferred = PrivateCorpusJSONShape.inspectRequest(body, contentType: nil)
        XCTAssertEqual(inferred.root, "form-like")
        XCTAssertEqual(inferred.fields, ["bookid": "string"])
        XCTAssertEqual(PrivateCorpusJSONShape.inspectRequest(body, contentType: "text/plain").root, "non-json")
        for malformed in ["bookid", "bookid=%GG", "bookid=%FF", "bookid=fixture&private-key=secret", "bookid=fixture&"] {
            XCTAssertEqual(PrivateCorpusJSONShape.inspectRequest(Data(malformed.utf8), contentType: nil).root, "non-json")
        }
        XCTAssertEqual(PrivateCorpusJSONShape.inspectRequest(Data(repeating: 65, count: 256 * 1024 + 1),
            contentType: "application/x-www-form-urlencoded").root, "over-size-limit")
    }

    func testImageTraceCorrelatesSamplePositionWithoutReusingCachedTransferEvidence() {
        let trace = PrivateCorpusImageTrace()
        let url = URL(string: "https://fixture.invalid/page.png?token=synthetic")!
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        trace.record(.init(urlSHA256: hash, httpStatusCode: nil, receivedBytes: 0,
            errorDomain: NSURLErrorDomain, errorCode: URLError.Code.cannotFindHost.rawValue))
        let first = trace.take(for: url, samplePosition: 8)
        XCTAssertEqual(first.samplePosition, 8)
        XCTAssertTrue(first.hasTransportObservation)
        XCTAssertEqual(first.errorCode, URLError.Code.cannotFindHost.rawValue)
        let second = trace.take(for: url, samplePosition: 16)
        XCTAssertFalse(second.hasTransportObservation)
        XCTAssertNil(second.errorCode)
        XCTAssertNil(second.httpStatusCode)
    }

    func testDistinguishesNullRootMissingDataNullDataAndEmptyArray() {
        XCTAssertEqual(PrivateCorpusJSONShape.inspect(Data("null".utf8)).root, "null")
        let missing = PrivateCorpusJSONShape.inspect(Data(#"{"code":0}"#.utf8))
        XCTAssertNil(missing.fields["data"])
        let null = PrivateCorpusJSONShape.inspect(Data(#"{"data":null,"success":false}"#.utf8))
        XCTAssertEqual(null.root, "object")
        XCTAssertEqual(null.fields["data"], "null")
        XCTAssertEqual(null.fields["success"], "boolean")
        XCTAssertEqual(PrivateCorpusJSONShape.inspect(Data(#"{"data":[]}"#.utf8)).fields["data"], "array:0")
    }

    func testBodyLimitAndMalformedResponseRemainExplicit() {
        XCTAssertEqual(PrivateCorpusJSONShape.inspect(Data()).root, "empty")
        XCTAssertEqual(PrivateCorpusJSONShape.inspect(Data("<html>login</html>".utf8)).root, "non-json")
        XCTAssertEqual(PrivateCorpusJSONShape.inspect(Data(repeating: 32, count: 256 * 1024 + 1)).root, "over-size-limit")
        let shape = PrivateCorpusJSONShape.inspect(Data(#"{"message":"请更新书源，token expired","data":null}"#.utf8))
        XCTAssertEqual(shape.reasonHints, ["authentication", "source-version"])
    }

    func testNestedFieldShapeIsBoundedIndependentlyOfResponseLength() throws {
        let keys = ["data", "result", "info", "sound", "content", "message"]
        let leaves = Dictionary(uniqueKeysWithValues: keys.map { ($0, "private-value") })
        let children = Dictionary(uniqueKeysWithValues: keys.map { ($0, leaves) })
        let root = Dictionary(uniqueKeysWithValues: keys.map { ($0, children) })
        let observed = PrivateCorpusJSONShape.inspect(try JSONSerialization.data(withJSONObject: root))
        XCTAssertEqual(observed.fields.count, 64)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(observed), as: UTF8.self).contains("private-value"))
    }

    func testMediaFieldShapesAndLiteralRuleFallbackContainNoResponseValues() throws {
        let body = #"{"info":{"sound":{"soundurl_128":null,"soundurl":"https://fixture.invalid/play?token=secret"}}}"#
        let chapter = BookChapter(title: "Fixture", url: "https://fixture.invalid/chapter", bookUrl: "https://fixture.invalid/book", index: 0)
        let observed = PrivateCorpusContentObservation(content: .init(chapter: chapter, title: "Fixture", paragraphs: [body]), rule: "$.info.sound.soundurl")
        XCTAssertEqual(observed.jsonShape.fields["info.sound.soundurl_128"], "null")
        XCTAssertEqual(observed.jsonShape.fields["info.sound.soundurl"], "string")
        XCTAssertTrue(observed.containsHTTPReference)
        XCTAssertFalse(observed.matchesContentRuleLiterally)
        let encoded = String(decoding: try JSONEncoder().encode(observed), as: UTF8.self)
        XCTAssertFalse(encoded.contains("secret"))
        XCTAssertFalse(encoded.contains("fixture.invalid"))
        let literal = PrivateCorpusContentObservation(content: .init(chapter: chapter, title: "Fixture", paragraphs: ["$.info.sound.soundurl"]), rule: "$.info.sound.soundurl")
        XCTAssertTrue(literal.matchesContentRuleLiterally)
    }

    func testTracePreservesResponseWithoutRetainingCredentialsOrResponseValues() async throws {
        let network = PrivateCorpusTraceFixtureNetwork()
        let trace = PrivateCorpusHTTPTrace(network: network)
        let result = await trace.load(makeRequest())
        let response = try result.get()
        XCTAssertEqual(response.body, network.body)
        let observations = await trace.snapshot()
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations[0].statusCode, 200)
        XCTAssertEqual(observations[0].responseShape?.fields["data"], "null")
        XCTAssertEqual(observations[0].requestShape.fields["app"], "string")
        let encoded = String(decoding: try JSONEncoder().encode(observations), as: UTF8.self)
        for secret in ["fixture.example", "private-book", "query-secret", "header-secret", "body-secret", "server-secret"] {
            XCTAssertFalse(encoded.contains(secret))
        }
    }

    func testTraceLimitDoesNotDropNetworkRequests() async {
        let network = PrivateCorpusTraceFixtureNetwork()
        let trace = PrivateCorpusHTTPTrace(network: network)
        for _ in 0..<70 { _ = await trace.load(makeRequest()) }
        let observations = await trace.snapshot()
        let dropped = await trace.droppedRequests
        let count = await network.callCount
        XCTAssertEqual(count, 70)
        XCTAssertEqual(observations.count, 64)
        XCTAssertEqual(dropped, 6)
        XCTAssertTrue(observations.allSatisfy { $0.outcome == "response" })
    }

    func testSnapshotShowsPendingRequestAndLaterCompletionSeparately() async {
        let network = PrivateCorpusSuspendedNetwork()
        let trace = PrivateCorpusHTTPTrace(network: network)
        let task = Task { await trace.load(self.makeRequest()) }
        await network.waitUntilRequested()
        let pending = await trace.snapshot()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].outcome, "pending")
        XCTAssertNil(pending[0].statusCode)
        await network.finish()
        _ = await task.value
        let completed = await trace.snapshot()
        XCTAssertEqual(completed[0].outcome, "failure")
        XCTAssertGreaterThanOrEqual(completed[0].elapsedMilliseconds, pending[0].elapsedMilliseconds)
    }

    private func makeRequest() -> SourceRequest {
        SourceRequest(url: URL(string: "https://fixture.example/private-book?token=query-secret")!, method: .post,
            headers: ["Authorization": "header-secret"], body: Data(#"{"app":"body-secret"}"#.utf8),
            expectedCharset: nil, timeout: 2)
    }
}

private actor PrivateCorpusTraceFixtureNetwork: SourceNetworkClient {
    let body = #"{"data":null,"message":"server-secret","access_token":"server-secret"}"#
    private(set) var callCount = 0

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        callCount += 1
        return .success(.init(url: request.url, statusCode: 200, headers: ["Set-Cookie": "server-secret"],
            body: body, data: Data(body.utf8)))
    }
}

private actor PrivateCorpusSuspendedNetwork: SourceNetworkClient {
    private var pending: CheckedContinuation<Result<SourceResponse, SourceEngineError>, Never>?
    private var requested: CheckedContinuation<Void, Never>?

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        await withCheckedContinuation { continuation in
            pending = continuation
            requested?.resume()
            requested = nil
        }
    }

    func waitUntilRequested() async {
        if pending != nil { return }
        await withCheckedContinuation { requested = $0 }
    }

    func finish() {
        pending?.resume(returning: .failure(.network("fixture token=server-secret")))
        pending = nil
    }
}
