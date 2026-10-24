import XCTest
@testable import SourceReadSwift

/// 滑动稳定性相关的两条纯策略。
/// 这两处一旦回归，表现就是「滑到章界卡一下」和「可见段落算错」，都在用户最容易注意到的位置。
final class ReaderScrollStabilityTests: XCTestCase {

    // MARK: - 重建推迟策略

    func testDefersOnlyWhenEverythingLinesUp() {
        XCTAssertTrue(ReaderRebuildDeferralPolicy.shouldDefer(
            textLayoutChanged: true, isAppend: false,
            hasPreviousConfiguration: true, userIsScrolling: true
        ))
    }

    func testAppendNeverDefers() {
        // 下一章正常续接走 fast-append，很便宜，不应该被推迟。
        XCTAssertFalse(ReaderRebuildDeferralPolicy.shouldDefer(
            textLayoutChanged: true, isAppend: true,
            hasPreviousConfiguration: true, userIsScrolling: true
        ))
    }

    func testFirstLoadNeverDefers() {
        // 首次装载没有旧配置可做锚点，推迟会导致空白。
        XCTAssertFalse(ReaderRebuildDeferralPolicy.shouldDefer(
            textLayoutChanged: true, isAppend: false,
            hasPreviousConfiguration: false, userIsScrolling: true
        ))
    }

    func testIdleUpdateNeverDefers() {
        XCTAssertFalse(ReaderRebuildDeferralPolicy.shouldDefer(
            textLayoutChanged: true, isAppend: false,
            hasPreviousConfiguration: true, userIsScrolling: false
        ))
    }

    func testUnchangedLayoutNeverDefers() {
        XCTAssertFalse(ReaderRebuildDeferralPolicy.shouldDefer(
            textLayoutChanged: false, isAppend: false,
            hasPreviousConfiguration: true, userIsScrolling: true
        ))
    }

    // MARK: - 可见段落解析（O(log n) 二分）

    private func ranges(_ lengths: [Int]) -> [NSRange] {
        var result: [NSRange] = []
        var cursor = 0
        for length in lengths {
            result.append(NSRange(location: cursor, length: length))
            cursor += length + 1  // 段间换行符
        }
        return result
    }

    func testVisibleStartInsideParagraph() {
        let r = ranges([10, 10, 10])
        XCTAssertEqual(ReaderParagraphIndexResolver.firstVisibleIndex(in: r, visibleRange: NSRange(location: 12, length: 5)), 1)
    }

    func testVisibleStartAtParagraphBoundary() {
        let r = ranges([10, 10, 10])
        // 第三段从 22 开始（10 + 1 + 10 + 1）。
        XCTAssertEqual(ReaderParagraphIndexResolver.firstVisibleIndex(in: r, visibleRange: NSRange(location: 22, length: 3)), 2)
    }

    func testVisibleStartOnSeparatorLine() {
        let r = ranges([10, 10, 10])
        // 位置 10 是段间换行符，应该落到下一段而不是上一段。
        let index = ReaderParagraphIndexResolver.firstVisibleIndex(in: r, visibleRange: NSRange(location: 10, length: 2))
        XCTAssertEqual(index, 1)
    }

    func testVisibleRangeBeyondContentReturnsNil() {
        let r = ranges([10, 10])
        XCTAssertNil(ReaderParagraphIndexResolver.firstVisibleIndex(in: r, visibleRange: NSRange(location: 500, length: 10)))
    }

    func testEmptyInputsReturnNil() {
        XCTAssertNil(ReaderParagraphIndexResolver.firstVisibleIndex(in: [], visibleRange: NSRange(location: 0, length: 5)))
        XCTAssertNil(ReaderParagraphIndexResolver.firstVisibleIndex(in: ranges([10]), visibleRange: NSRange(location: 0, length: 0)))
    }
}
