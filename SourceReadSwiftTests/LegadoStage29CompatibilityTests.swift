import Foundation
import XCTest
@testable import SourceReadSwift

/// End-to-end regression coverage for the Stage 29 Legado compatibility
/// matrix.  The fixture intentionally mixes JSON and HTML responses and
/// changes request state after every phase, which catches parser-only tests
/// that never exercise the real Search -> Detail -> TOC -> Content chain.
final class LegadoStage29CompatibilityTests: XCTestCase {
    func testSearchDetailTOCMixedPaginationAndContentWithDynamicState() async throws {
        let source = try loadFixture(named: "legado-stage29-matrix-source")
        let network = Stage29MatrixNetwork()
        let diagnostics = DiagnosticCollector()
        let engine = LegadoSourceEngine(network: network, diagnostics: diagnostics.sink)

        let search = try unwrap(await engine.searchBooks(source: source, keyword: "Matrix Reader", page: 1))
        XCTAssertEqual(search.map(\.name), ["Matrix Reader"])
        XCTAssertEqual(search.first?.bookUrl, "https://fixture.example/stage29/book/1")

        let detail = try unwrap(await engine.getBookDetail(source: source, book: try XCTUnwrap(search.first)))
        XCTAssertEqual(detail.name, "Matrix Reader")
        XCTAssertEqual(detail.tocUrl, "https://fixture.example/stage29/toc?page=1")

        let chapters = try unwrap(await engine.getChapterList(source: source, book: detail))
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章", "第三章"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
        XCTAssertEqual(chapters.map(\.url), [
            "https://fixture.example/stage29/chapter/1",
            "https://fixture.example/stage29/chapter/2",
            "https://fixture.example/stage29/chapter/3"
        ])

        let content = try unwrap(await engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))
        XCTAssertEqual(content.paragraphs, ["第一段", "第二段", "第三段", "第四段"])
        XCTAssertNil(content.nextContentUrl)

        let requests = network.requests
        XCTAssertEqual(requests.map { $0.url.absoluteString }, [
            "https://fixture.example/stage29/search?q=Matrix%20Reader&page=1",
            "https://fixture.example/stage29/book/1",
            "https://fixture.example/stage29/toc?page=1",
            "https://fixture.example/stage29/toc?page=2",
            "https://fixture.example/stage29/chapter/1",
            "https://fixture.example/stage29/chapter/1?page=2"
        ])
        XCTAssertEqual(requests.map { header("X-Stage-Token", in: $0) ?? "" }, [
            "{{token}}", "detail-token", "toc-token", "content-token", "content-token", "content-token"
        ])
        XCTAssertEqual(requests.map { header("X-Stage", in: $0) ?? "" }, [
            "{{phase}}", "search", "detail", "toc", "toc", "content"
        ])
        XCTAssertNil(header("Cookie", in: requests[0]))
        XCTAssertEqual(requests.dropFirst().map { header("Cookie", in: $0) ?? "" }, Array(repeating: "session=stage29", count: 5))

        let evidence = SourceDiagnosticStage.allCases.reduce(into: [SourceDiagnosticStage: SourceDiagnosticEvidence]()) { result, stage in
            result[stage] = engine.diagnosticEvidence(sourceURL: source.bookSourceUrl, stage: stage)
        }
        for stage in SourceDiagnosticStage.allCases {
            let item = try XCTUnwrap(evidence[stage], "missing \(stage.rawValue) evidence")
            XCTAssertEqual(item.requestMethod, "GET")
            XCTAssertEqual(item.responseStatusCode, 200)
            XCTAssertFalse(item.responseHeaders.isEmpty)
            XCTAssertTrue(item.finalURL.hasPrefix("https://fixture.example/stage29/"))
            XCTAssertGreaterThan(item.responseDecodedByteCount, 0)
            XCTAssertTrue(item.javascript.contains { $0.succeeded })
        }
        XCTAssertTrue(evidence[.search]?.responseHeaders.keys.contains { $0.caseInsensitiveCompare("Set-Cookie") == .orderedSame } == true)
        XCTAssertTrue(evidence[.search]?.javascript.contains { $0.succeeded } == true)
        XCTAssertTrue(evidence[.content]?.javascript.contains { $0.succeeded } == true)

        let snapshot = diagnostics.snapshot()
        let observedStages = Set(snapshot.map(\.stage))
        XCTAssertTrue(observedStages.contains("search.load.response"))
        XCTAssertTrue(observedStages.contains("detail.load.response"))
        XCTAssertTrue(observedStages.contains("toc.load.response"))
        XCTAssertTrue(observedStages.contains("toc.next.load.response"))
        XCTAssertTrue(observedStages.contains("content.load.response"))
        XCTAssertTrue(observedStages.contains("content.next.load.response"))

        // The exported diagnostic path must redact both dynamic headers and
        // Set-Cookie values while preserving their field names/presence.
        let reportEngine = LegadoSourceEngine(network: Stage29MatrixNetwork())
        let execution = await reportEngine.runPipelineReport(source: source, keyword: "Matrix Reader", timeout: 5)
        XCTAssertNil(execution.error)
        let report = execution.result.report
        let exported = String(decoding: try JSONEncoder().encode(report), as: UTF8.self)
        XCTAssertTrue(exported.contains("<redacted>"))
        XCTAssertFalse(exported.contains("detail-token"))
        XCTAssertFalse(exported.contains("toc-token"))
        XCTAssertFalse(exported.contains("content-token"))
        XCTAssertFalse(exported.contains("session=stage29"))
    }

    func testFinalURLRedirectLoopEmitsDuplicateFinalURLAndRetainsChapters() async throws {
        let source = try loadFixture(named: "legado-stage29-matrix-source")
        let network = Stage29RedirectLoopNetwork()
        let diagnostics = DiagnosticCollector()
        let engine = LegadoSourceEngine(network: network, diagnostics: diagnostics.sink)
        let detail = BookDetail(
            name: "Matrix Reader",
            author: "Fixture Author",
            coverUrl: nil,
            bookUrl: "https://fixture.example/stage29/book/1",
            tocUrl: "https://fixture.example/stage29/toc?page=1",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil,
            latestChapter: nil
        )

        let result = try unwrap(await engine.getChapterList(source: source, book: detail))
        XCTAssertEqual(result.map(\.title), ["第一章", "第二章"])
        let stop = diagnostics.snapshot().first { $0.stage == "toc.pagination.stop" }
        XCTAssertEqual(stop?.details["reason"], "duplicate-final-url")
        XCTAssertEqual(stop?.details["pagesLoaded"], "1")
        XCTAssertEqual(stop?.details["retainedItemCount"], "2")
    }

    private func loadFixture(named name: String) throws -> BookSource {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
                ?? bundle.url(forResource: name, withExtension: "json")
        )
        return try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: url))
    }

    private func unwrap<T>(_ result: Result<T, SourceEngineError>, file: StaticString = #filePath, line: UInt = #line) throws -> T {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            XCTFail("stage 29 fixture failed: \(error)", file: file, line: line)
            throw error
        }
    }

    private func header(_ name: String, in request: SourceRequest) -> String? {
        request.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

private final class DiagnosticCollector: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [DiagnosticEvent] = []

    var sink: DiagnosticSink {
        DiagnosticSink { [weak self] event in
            self?.lock.lock()
            self?.events.append(event)
            self?.lock.unlock()
        }
    }

    func snapshot() -> [DiagnosticEvent] {
        lock.lock(); defer { lock.unlock() }
        return events
    }
}

private final class Stage29MatrixNetwork: SourceNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedRequests: [SourceRequest] = []

    var requests: [SourceRequest] {
        lock.lock(); defer { lock.unlock() }
        return recordedRequests
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        lock.lock()
        recordedRequests.append(request)
        lock.unlock()

        let url = request.url.absoluteString
        let token = request.headers.first { $0.key.caseInsensitiveCompare("X-Stage-Token") == .orderedSame }?.value
        let phase = request.headers.first { $0.key.caseInsensitiveCompare("X-Stage") == .orderedSame }?.value
        let expected: (String, String)
        switch request.url.path {
        case "/stage29/search": expected = ("{{token}}", "{{phase}}")
        case "/stage29/book/1": expected = ("detail-token", "search")
        case "/stage29/toc": expected = request.url.query == "page=1" ? ("toc-token", "detail") : ("content-token", "toc")
        case "/stage29/chapter/1": expected = request.url.query == nil ? ("content-token", "toc") : ("content-token", "content")
        default: expected = ("", "")
        }
        guard token == expected.0, phase == expected.1 else {
            return .failure(.network("stage29 dynamic header mismatch for \(url)"))
        }
        let body: String
        let headers: [String: String]
        switch request.url.path {
        case "/stage29/search":
            body = try! fixtureBody("legado-stage29-search", extension: "html")
            headers = ["Content-Type": "application/json; charset=utf-8", "Set-Cookie": "session=stage29; Path=/"]
        case "/stage29/book/1":
            body = try! fixtureBody("legado-stage29-detail", extension: "json")
            headers = ["Content-Type": "application/json"]
        case "/stage29/toc":
            if request.url.query == "page=1" {
                body = try! fixtureBody("legado-stage29-toc-page-1", extension: "json")
                headers = ["Content-Type": "application/json"]
            } else {
                body = try! fixtureBody("legado-stage29-toc-page-2", extension: "html")
                headers = ["Content-Type": "text/html; charset=utf-8"]
            }
        case "/stage29/chapter/1":
            if request.url.query == nil {
                body = try! fixtureBody("legado-stage29-content-page-1", extension: "json")
                headers = ["Content-Type": "application/json"]
            } else {
                body = try! fixtureBody("legado-stage29-content-page-2", extension: "html")
                headers = ["Content-Type": "text/html; charset=utf-8"]
            }
        default:
            return .failure(.network("fixture response missing for \(url)"))
        }
        return .success(SourceResponse(url: request.url, statusCode: 200, headers: headers, body: body, data: Data(body.utf8)))
    }
}

private final class Stage29RedirectLoopNetwork: SourceNetworkClient, @unchecked Sendable {
    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let body: String
        let responseURL: URL
        let headers: [String: String]
        if request.url.query == "page=1" {
            body = try! fixtureBody("legado-stage29-toc-page-1", extension: "json")
            responseURL = request.url
            headers = ["Content-Type": "application/json"]
        } else {
            // The next URL redirects back to page 1.  The engine must stop on
            // the canonical final URL without discarding page 1's chapters.
            body = try! fixtureBody("legado-stage29-toc-page-1", extension: "json")
            responseURL = URL(string: "https://fixture.example/stage29/toc?page=1")!
            headers = ["Content-Type": "application/json"]
        }
        return .success(SourceResponse(url: responseURL, statusCode: 200, headers: headers, body: body, data: Data(body.utf8)))
    }
}

private func fixtureBody(_ name: String, extension fileExtension: String) throws -> String {
    // Test bundles copy Fixtures as resources; this helper is intentionally
    // independent from XCTest so the network doubles can remain private.
    let candidates = [
        Bundle(for: LegadoStage29CompatibilityTests.self).url(forResource: name, withExtension: fileExtension, subdirectory: "Fixtures"),
        Bundle(for: LegadoStage29CompatibilityTests.self).url(forResource: name, withExtension: fileExtension)
    ]
    guard let url = candidates.compactMap({ $0 }).first else {
        throw NSError(domain: "Stage29Fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name).\(fileExtension)"])
    }
    return try String(contentsOf: url, encoding: .utf8)
}
