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
}
