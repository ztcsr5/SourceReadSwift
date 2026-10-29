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
}
