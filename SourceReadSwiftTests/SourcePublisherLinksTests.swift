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

    func testVersionPageUsesOnlyLiteralHTTPSImportDeclarations() {
        let html = #"""
        <p><a href="https://reader.invalid/reader.apk">下载阅读客户端</a></p>
        <script>
        const serverConfig = {
          main: { name: '主线路', icon: 'rocket', baseUrl: 'https://publisher.invalid', downloadPath: '/export/%E6%9B%B4%E6%96%B0.json' },
          mirror: { name: "镜像", icon: "box", baseUrl: "https://mirror.invalid/base", downloadPath: "/export/rules.json" },
          same: { name: '重复', baseUrl: 'https://publisher.invalid', downloadPath: '/export/%E6%9B%B4%E6%96%B0.json' },
          insecure: { name: '明文', baseUrl: 'http://publisher.invalid', downloadPath: '/rules.json' },
          embedded: { name: '凭据', baseUrl: 'https://user@publisher.invalid', downloadPath: '/rules.json' },
          relativeHost: { name: '跨域', baseUrl: 'https://publisher.invalid', downloadPath: '//other.invalid/rules.json' },
          gated: { name: '会话', baseUrl: 'https://publisher.invalid', downloadPath: '/rules.json?token=fixture' },
          dynamic: { name: '动态', baseUrl: host, downloadPath: '/rules.json' }
        };
        function render() {
          return Object.values(serverConfig).map(server => {
            const fullUrl = server.baseUrl + server.downloadPath;
            return `<a href="yuedu://booksource/importonline?src=${encodeURIComponent(fullUrl)}">${server.name}</a>`;
          });
        }
        </script>
        """#
        let links = SourcePublisherLinks.linksForSourceAction(in: html)
        XCTAssertEqual(links.map(\.title), ["主线路", "镜像"])
        XCTAssertEqual(links.map(\.url.absoluteString),
            ["https://publisher.invalid/export/%E6%9B%B4%E6%96%B0.json", "https://mirror.invalid/base/export/rules.json"])
        XCTAssertTrue(links.allSatisfy { !$0.isPageReference })
    }

    func testVersionPageDoesNotGuessRuntimeMirrorsOrExecuteItsScript() {
        let html = #"""
        <script>
        const serverConfig = {
          main: {
            name: '主线路导入',
            icon: 'rocket',
            baseUrl: 'https://publisher.invalid',
            downloadPath: '/更新.json'
          }
        };
        hosts.forEach(host => {
          serverConfig[host] = { name: '动态镜像', baseUrl: host, downloadPath: '/other/rules.json' };
        });
        fetch('https://unrelated.invalid/private');
        buttonGroup.innerHTML = Object.values(serverConfig).map(server => {
          const fullUrl = server.baseUrl + server.downloadPath;
          return `<a href="yuedu://booksource/importonline?src=${encodeURIComponent(fullUrl)}">导入</a>`;
        }).join('');
        </script>
        """#
        XCTAssertEqual(SourcePublisherLinks.linksForSourceAction(in: html).map(\.url.absoluteString),
            ["https://publisher.invalid/%E6%9B%B4%E6%96%B0.json"])
    }
}
