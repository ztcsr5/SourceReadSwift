import XCTest
@testable import SourceReadSwift

final class SourcePublisherLinksTests: XCTestCase {
    private let pageURL = URL(string: "https://publisher.example/catalog/index.html")!

    func testExtractsVisibleImportsAndLiteralSameOriginGETReferences() throws {
        let html = #"""
        <html><a href="../books.json">书源甲</a><a href="../books.json">重复</a>
        <a href="javascript:alert(1)">导入</a><a href="https://user:secret@evil.example/a.json">导入</a>
        <script>fetch('api/list.php'); fetch('api/record.php', {method:'POST'});
        fetch('https://other.example/list'); fetch(dynamicURL);</script></html>
        """#
        let page = try XCTUnwrap(SourcePublisherLinks.discover(in: html, at: pageURL))
        XCTAssertEqual(page.links.map(\.url.absoluteString), ["https://publisher.example/books.json", "https://publisher.example/catalog/api/list.php"])
        XCTAssertEqual(page.links.map(\.isPageReference), [false, true])
    }

    func testPublisherJSONOffersNamedDownloadsInsteadOfImportingCatalogRows() throws {
        let json = #"[{"name":"甲","url":"https://download.example/a.json","bookSourceUrl":"https://source.example"}]"#
        let page = try XCTUnwrap(SourcePublisherLinks.discover(in: json, at: pageURL))
        XCTAssertEqual(page.links.first?.title, "甲")
        XCTAssertEqual(page.links.first?.url.absoluteString, "https://download.example/a.json")
    }

    func testValidSourceJSONIsNeverReclassifiedAsPublisher() {
        let json = #"[{"bookSourceName":"甲","bookSourceUrl":"https://source.example","url":"https://download.example/a.json","ruleSearch":{"name":"a@text"}}]"#
        XCTAssertNil(SourcePublisherLinks.discover(in: json, at: pageURL))
        XCTAssertNil(SourcePublisherLinks.discover(in:
            #"[{"name":"旧格式","url":"https://source.example","ruleSearchList":".book"}]"#, at: pageURL))
        XCTAssertNil(SourcePublisherLinks.discover(in: "<html><body>404 Not Found</body></html>", at: pageURL))
    }

    func testReaderImportLinkAndPublisherLimit() throws {
        let html = "<a href='yuedu://booksource/import?src=https%3A%2F%2Fexample.com%2Fsource.json'>导入</a>"
        XCTAssertEqual(SourcePublisherLinks.discover(in: html, at: pageURL)?.links.first?.url.absoluteString,
            "https://example.com/source.json")
        let rows = (0..<250).map { ["name": "源\($0)", "url": "https://example.com/\($0).json"] }
        let text = String(decoding: try JSONEncoder().encode(rows), as: UTF8.self)
        XCTAssertEqual(SourcePublisherLinks.discover(in: text, at: pageURL)?.links.count, 200)
    }
}
