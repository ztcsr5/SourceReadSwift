import XCTest
@testable import SourceReadSwift

final class SourceDebugReadabilityTests: XCTestCase {
    func testEmptyContentDoesNotPassReadabilityCheck() {
        XCTAssertFalse(SourceChapterNotice.isReadableContent(paragraphs: [], chapterTitle: "第一章"))
        XCTAssertFalse(SourceChapterNotice.isReadableContent(paragraphs: ["   "], chapterTitle: "第一章"))
    }

    func testUpdateGateDoesNotPassReadabilityCheck() {
        let paragraphs = ["当前书源版本过低，请更新书源"]
        XCTAssertTrue(SourceChapterNotice.requiresUpdate(paragraphs: paragraphs, chapterTitle: "第一章"))
        XCTAssertFalse(SourceChapterNotice.isReadableContent(paragraphs: paragraphs, chapterTitle: "第一章"))
    }

    func testActualChapterTextPassesReadabilityCheck() {
        XCTAssertTrue(SourceChapterNotice.isReadableContent(
            paragraphs: ["夜色渐深，山路尽头亮起一盏灯。"],
            chapterTitle: "第一章"
        ))
    }

    func testWholeChapterRateLimitNoticesAreNotReadable() {
        // Synthetic notices exercise classification without claiming a live-source replay.
        for notice in [
            "您的账号因访问过快已被暂时封禁，请在1分钟后重试。",
            "請求過於頻繁，請稍後重試。",
            "访问过于频繁，请等待60秒后重试。"
        ] {
            let paragraphs = ["第一章", notice, "也可以开通VIP解除访问限制。", "❔"]
            let message = SourceChapterNotice.rateLimitMessage(paragraphs: paragraphs, chapterTitle: "第一章")
            XCTAssertTrue(message?.contains(notice) == true)
            XCTAssertFalse(SourceChapterNotice.isReadableContent(paragraphs: paragraphs, chapterTitle: "第一章"))
        }
    }

    func testRateLimitQuotesAndOrdinaryPaidChaptersRemainReadable() {
        let notice = "您的账号因访问过快已被暂时封禁，请在1分钟后重试。"
        for paragraphs in [
            [notice, "他看完屏幕上的提示，关掉电脑，出门去买晚饭。"],
            ["屏幕显示：" + notice],
            ["本章为VIP章节，请登录后购买阅读。"],
            ["您的账号已被永久封禁，请联系客服。"]
        ] {
            XCTAssertNil(SourceChapterNotice.rateLimitMessage(paragraphs: paragraphs, chapterTitle: "第一章"))
            XCTAssertTrue(SourceChapterNotice.isReadableContent(paragraphs: paragraphs, chapterTitle: "第一章"))
        }
    }
}
