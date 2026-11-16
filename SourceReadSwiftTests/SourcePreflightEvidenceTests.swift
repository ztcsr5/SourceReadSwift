import Foundation
import XCTest
@testable import SourceReadSwift

final class SourcePreflightEvidenceTests: XCTestCase {
    func testHeaderFailureRetainsJavaScriptEvidenceWithoutInventingARequest() async throws {
        let source = BookSource(bookSourceName: "Synthetic preflight", bookSourceUrl: "https://preflight.fixture.invalid",
            searchUrl: "/search", header: "@js: missingHeaderFunction();")
        try await assertFailureEvidence(source: source, missingName: "missingHeaderFunction")
    }

    func testURLFailureRetainsJavaScriptEvidenceWithoutInventingARequest() async throws {
        let source = BookSource(bookSourceName: "Synthetic preflight", bookSourceUrl: "https://preflight.fixture.invalid",
            searchUrl: "@js: missingURLFunction();")
        try await assertFailureEvidence(source: source, missingName: "missingURLFunction")
    }

    private func assertFailureEvidence(source: BookSource, missingName: String) async throws {
        let network = PreflightEvidenceNetwork()
        let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil))
        engine.allowWebViewFallback = false
        let execution = await engine.runPipelineReport(source: source, keyword: "fixture", timeout: 5,
            tocMaxPages: 1, contentMaxPages: 1)
        XCTAssertNotNil(execution.error)
        let sent = await network.requests
        XCTAssertEqual(sent, 0)
        let step = try XCTUnwrap(execution.result.steps.first)
        let failures = try XCTUnwrap(step.javascript).filter { !$0.succeeded }
        XCTAssertTrue(failures.contains { $0.exception?.contains(missingName) == true })
        XCTAssertEqual(step.requestMethod, "")
        XCTAssertEqual(step.finalURL, "")
        XCTAssertEqual(step.responseStatusCode, 0)
        XCTAssertTrue(step.executionLogs?.contains("No top-level HTTP request was issued in this stage") == true)
    }
}

private actor PreflightEvidenceNetwork: SourceNetworkClient {
    private(set) var requests = 0

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        requests += 1
        return .failure(.network("Unexpected fixture transport"))
    }
}
