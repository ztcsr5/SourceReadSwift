import Foundation
import XCTest
@testable import SourceReadSwift

final class PrivateCorpusHTTPTraceTests: XCTestCase {
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
