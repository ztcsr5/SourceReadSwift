import Foundation
import XCTest
@testable import SourceReadSwift

/// Native `@put` / `@get` directives are a distinct path from `java.put`:
/// the JSON extractor writes the value into the shared execution context and
/// a later engine stage must be able to consume it.  This test exercises the
/// real Search -> Detail -> TOC -> Content pipeline instead of a single
/// extractor instance, because the engine rebuilds extractors per stage.
final class SourceEngineNativeDirectiveTests: XCTestCase {
    func testMultiFieldPutPersistsAcrossSearchDetailTocAndContent() async throws {
        let source = BookSource(
            bookSourceName: "Native directive pipeline",
            bookSourceUrl: "https://fixture.local/",
            searchUrl: "https://fixture.local/search?q={{key}}",
            ruleSearch: SourceRule(fields: [
                "bookList": "@put:{toc:$.meta.toc, token:$.meta.token}$.books",
                "name": "$.name",
                "author": "$.author",
                "bookUrl": "$.url"
            ]),
            ruleBookInfo: SourceRule(fields: [
                "name": "$.name",
                "author": "$.author",
                "tocUrl": "@get:{toc}?token=@get:{token}"
            ]),
            ruleToc: SourceRule(fields: [
                "chapterList": "$.chapters",
                "chapterName": "$.title",
                "chapterUrl": "$.url"
            ]),
            ruleContent: SourceRule(fields: [
                "content": "$.content"
            ]),
            header: #"{"X-Token":"{{token}}"}"#
        )
        let network = NativeDirectiveNetwork()
        let engine = LegadoSourceEngine(network: network)

        let books = try unwrap(await engine.searchBooks(source: source, keyword: "swift", page: 1))
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(book.name, "Native @put")
        XCTAssertEqual(book.bookUrl, "https://fixture.local/book/1")

        let detail = try unwrap(await engine.getBookDetail(source: source, book: book))
        XCTAssertEqual(detail.name, "Native @put")
        XCTAssertEqual(detail.tocUrl, "https://fixture.local/toc/1?token=abc123")

        let chapters = try unwrap(await engine.getChapterList(source: source, book: detail))
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters.first?.title, "第一章")
        XCTAssertEqual(chapters.first?.url, "https://fixture.local/chapter/1")

        let content = try unwrap(await engine.getContent(source: source, chapter: try XCTUnwrap(chapters.first)))
        XCTAssertEqual(content.paragraphs, ["原生 @put 正文"])

        // The search request cannot resolve the token yet; every later stage
        // must expand the value written by the search-stage `@put`.
        XCTAssertEqual(network.paths, ["/search", "/book/1", "/toc/1", "/chapter/1"])
        XCTAssertEqual(network.tokens, ["{{token}}", "abc123", "abc123", "abc123"])
        XCTAssertEqual(network.tocTokenQueries, ["abc123"])
    }

    private func unwrap<T>(_ result: Result<T, SourceEngineError>) throws -> T {
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            XCTFail("pipeline failed: \(error)")
            throw error
        }
    }
}

private final class NativeDirectiveNetwork: SourceNetworkClient, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var paths: [String] = []
    private(set) var tokens: [String] = []
    private(set) var tocTokenQueries: [String] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let token = request.headers.first {
            $0.key.caseInsensitiveCompare("X-Token") == .orderedSame
        }?.value ?? ""
        lock.lock()
        paths.append(request.url.path)
        tokens.append(token)
        if request.url.path == "/toc/1",
           let query = request.url.query,
           let value = URLComponents(string: "https://fixture.local/?\(query)")?
               .queryItems?.first(where: { $0.name == "token" })?.value {
            tocTokenQueries.append(value)
        }
        lock.unlock()

        switch request.url.path {
        case "/search":
            return .success(response(
                request,
                #"{"meta":{"toc":"/toc/1","token":"abc123"},"books":[{"name":"Native @put","url":"/book/1"}]}"#
            ))
        case "/book/1":
            return .success(response(request, #"{"name":"Native @put"}"#))
        case "/toc/1":
            return .success(response(request, #"{"chapters":[{"title":"第一章","url":"/chapter/1"}]}"#))
        case "/chapter/1":
            return .success(response(request, #"{"content":"原生 @put 正文"}"#))
        default:
            return .failure(.network("unexpected native directive URL: \(request.url.absoluteString)"))
        }
    }

    private func response(_ request: SourceRequest, _ body: String) -> SourceResponse {
        SourceResponse(
            url: request.url,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: body,
            data: Data(body.utf8)
        )
    }
}