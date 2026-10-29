import XCTest
@testable import SourceReadSwift

final class JavaScriptChallengeDetectionTests: XCTestCase {
    func testDetectsWtzwArg1BootstrapShell() {
        let body = #"""
        <html><head><script>
        var arg1='9F0C2A8E5B7D4C1A6F3E2D9B8A7C6E5D';
        function getRenderData(){document.cookie=arg1+';path=/';location.reload();}
        </script></head><body>loading</body></html>
        """#
        XCTAssertTrue(LegadoSourceEngine.looksLikeJavaScriptChallenge(body))
    }

    func testDetectsCookieReloadShellWithoutArticleMarkup() {
        let body = "<html><script>document.cookie='ok=1';location.reload()</script><body>checking</body></html>"
        XCTAssertTrue(LegadoSourceEngine.looksLikeJavaScriptChallenge(body))
    }

    func testDoesNotFlagNormalSearchMarkup() {
        let body = "<html><body><ul><li><a href='/book/1'>斗破苍穹</a></li></ul></body></html>"
        XCTAssertFalse(LegadoSourceEngine.looksLikeJavaScriptChallenge(body))
    }

    func testDoesNotFlagArticleThatWritesCookies() {
        let body = "<html><body><article>正文</article><script>document.cookie='theme=dark'</script></body></html>"
        XCTAssertFalse(LegadoSourceEngine.looksLikeJavaScriptChallenge(body))
    }

    func testEmptyBodyIsNotAChallenge() {
        XCTAssertFalse(LegadoSourceEngine.looksLikeJavaScriptChallenge(""))
    }

    func testPostOriginKeepsNonDefaultPort() {
        let source = BookSource(
            bookSourceName: "LAN fixture",
            bookSourceUrl: "http://192.168.1.10:8080",
            customConfig: #"{"method":"POST","body":"q=1"}"#
        )
        let request = SourceRequestBuilder().buildPageRequest(
            source: source,
            urlText: "http://192.168.1.10:8080/api/search"
        )
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.headers["Origin"], "http://192.168.1.10:8080")
        XCTAssertEqual(request.headers["Referer"], "http://192.168.1.10:8080/")
    }
}
