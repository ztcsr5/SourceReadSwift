import XCTest
@testable import SourceReadSwift

/// Guards the WebView fallback classifier. A full result page that merely
/// mentions a CDN brand in its footer must never be treated as an anti-bot
/// interstitial: the WebKit fallback returns a simplified DOM and every rule
/// target disappears (qunxs shipped 15 items over HTTP and parsed 0 after
/// the fallback).
final class WebViewFallbackHeuristicTests: XCTestCase {

    private func qunxsResultPage() -> String {
        var html = "<!DOCTYPE html><html><head><title>搜索结果</title></head><body>"
        html += "<nav><ul><li><a href=\"/\">首页</a></li><li><a href=\"/top\">排行</a></li></ul></nav>"
        for index in 0..<15 {
            html += "<div class=\"item\"><dl><dt><a href=\"/xiaoshuo_\(index).html\">书名\(index)</a></dt>"
            html += "<dd>简介\(index)</dd></dl></div>"
        }
        html += "<footer>Performance &amp; security by Cloudflare</footer></body></html>"
        return html
    }

    func testResultPageWithCloudflareFooterIsCrawlable() {
        XCTAssertTrue(LegadoSourceEngine.hasCrawlableMarkup(qunxsResultPage()))
    }

    func testCloudflareInterstitialHasNoCrawlableMarkup() {
        let body = "<html><head><title>Just a moment...</title></head><body>"
            + "<div id=\"challenge\">Checking your browser before accessing the site.</div>"
            + "<noscript>Enable JavaScript and cookies to continue</noscript></body></html>"
        XCTAssertFalse(LegadoSourceEngine.hasCrawlableMarkup(body))
    }

    func testEmptyBodyHasNoCrawlableMarkup() {
        XCTAssertFalse(LegadoSourceEngine.hasCrawlableMarkup(""))
    }

    func testAnchorDensePageIsCrawlable() {
        var body = "<html><body>"
        for index in 0..<8 { body += "<a href=\"/book/\(index)\">书\(index)</a>" }
        body += "</body></html>"
        XCTAssertTrue(LegadoSourceEngine.hasCrawlableMarkup(body))
    }

    func testTablePageIsCrawlable() {
        XCTAssertTrue(LegadoSourceEngine.hasCrawlableMarkup("<html><body><table><tr><td>a</td></tr></table></body></html>"))
    }

    func testChallengeShellStillDetected() {
        XCTAssertTrue(LegadoSourceEngine.looksLikeJavaScriptChallenge("<script>var arg1=\"x\";</script>"))
        XCTAssertTrue(LegadoSourceEngine.looksLikeJavaScriptChallenge("<script>getRenderData(123)</script>"))
    }

    func testNormalSearchPageIsNotAChallengeShell() {
        XCTAssertFalse(LegadoSourceEngine.looksLikeJavaScriptChallenge(qunxsResultPage()))
    }

    // MARK: - URL option `webView` with a POST body

    private func request(method: SourceHTTPMethod, body: Data?, webView: Bool = true) -> SourceRequest {
        SourceRequest(
            url: URL(string: "https://m.douxsw.com/search/")!,
            method: method,
            headers: [:],
            body: body,
            expectedCharset: nil,
            timeout: 15,
            webView: webView
        )
    }

    /// 抖音小说 sends `searchkey` as a POST body together with `webView:true`.
    /// WKWebView can only navigate with GET, so forcing WebKit first dropped the
    /// body and returned the 2.8KB empty form instead of the 5KB result page.
    func testPostBodyWithWebViewOptionProbesSocketFirst() {
        let req = request(method: .post, body: Data("searchkey=剑来".utf8))
        XCTAssertFalse(LegadoSourceEngine.shouldForceWebView(for: req))
    }

    func testGetWithWebViewOptionStillRenders() {
        let req = request(method: .get, body: nil)
        XCTAssertTrue(LegadoSourceEngine.shouldForceWebView(for: req))
    }

    func testPostWithoutBodyStillRenders() {
        let req = request(method: .post, body: nil)
        XCTAssertTrue(LegadoSourceEngine.shouldForceWebView(for: req))
    }

    func testWebViewOptionFalseNeverForcesWebKit() {
        let req = request(method: .get, body: nil, webView: false)
        XCTAssertFalse(LegadoSourceEngine.shouldForceWebView(for: req))
    }
}
