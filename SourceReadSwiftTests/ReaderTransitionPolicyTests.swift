import XCTest
import SwiftUI
@testable import SourceReadSwift

/// 覆盖层过渡策略的纯函数测试。不需要 UI 就能验证几何与判定。
final class ReaderTransitionPolicyTests: XCTestCase {
    func testDismissalProgressTracksFingerWithinBounds() {
        XCTAssertEqual(ReaderTransitionPolicy.dismissalProgress(translation: 0, width: 400), 0)
        XCTAssertEqual(ReaderTransitionPolicy.dismissalProgress(translation: 100, width: 400), 0.25)
        XCTAssertEqual(ReaderTransitionPolicy.dismissalProgress(translation: 400, width: 400), 1)
        // 越界不产生负进度
        XCTAssertEqual(ReaderTransitionPolicy.dismissalProgress(translation: -80, width: 400), 0)
        XCTAssertEqual(ReaderTransitionPolicy.dismissalProgress(translation: 900, width: 400), 1)
        // 宽度未知时不推进，避免除零
        XCTAssertEqual(ReaderTransitionPolicy.dismissalProgress(translation: 120, width: 0), 0)
    }

    func testShouldDismissUsesDistanceAndVelocity() {
        let width: CGFloat = 400
        // 距离过半 → 完成
        XCTAssertTrue(ReaderTransitionPolicy.shouldDismiss(translation: 200, velocity: 0, width: width))
        // 距离不足且速度慢 → 取消
        XCTAssertFalse(ReaderTransitionPolicy.shouldDismiss(translation: 40, velocity: 0, width: width))
        // 距离虽短但甩得足够快 → 完成
        XCTAssertTrue(ReaderTransitionPolicy.shouldDismiss(translation: 20, velocity: 1200, width: width))
        // 反向速度一律取消，避免"想收回却被丢出去"
        XCTAssertFalse(ReaderTransitionPolicy.shouldDismiss(translation: 300, velocity: -1200, width: width))
        XCTAssertFalse(ReaderTransitionPolicy.shouldDismiss(translation: 300, velocity: 0, width: 0))
    }

    func testTargetRectInterpolatesFromCoverToFullScreen() {
        let screen = CGSize(width: 390, height: 844)
        let cover = CGRect(x: 20, y: 120, width: 100, height: 140)

        let closed = ReaderTransitionPolicy.targetRect(cover: cover, screen: screen, progress: 0)
        XCTAssertEqual(closed.origin.x, cover.origin.x, accuracy: 0.01)
        XCTAssertEqual(closed.width, cover.width, accuracy: 0.01)

        let open = ReaderTransitionPolicy.targetRect(cover: cover, screen: screen, progress: 1)
        XCTAssertEqual(open.origin.x, 0, accuracy: 0.01)
        XCTAssertEqual(open.origin.y, 0, accuracy: 0.01)
        XCTAssertEqual(open.width, screen.width, accuracy: 0.01)
        XCTAssertEqual(open.height, screen.height, accuracy: 0.01)

        // 中点单调，不发生回折
        let mid = ReaderTransitionPolicy.targetRect(cover: cover, screen: screen, progress: 0.5)
        XCTAssertGreaterThan(mid.width, cover.width)
        XCTAssertLessThan(mid.width, screen.width)
    }

    func testContentAndCoverOpacityAreHandedOver() {
        // 正文在几何落位前不可见，避免"文字跟着缩放"
        XCTAssertEqual(ReaderTransitionPolicy.contentOpacity(progress: 0), 0)
        XCTAssertEqual(ReaderTransitionPolicy.contentOpacity(progress: 0.6), 0, accuracy: 0.0001)
        XCTAssertEqual(ReaderTransitionPolicy.contentOpacity(progress: 1), 1, accuracy: 0.0001)
        // 封面在正文接管时已经淡出，不会出现两个封面
        XCTAssertEqual(ReaderTransitionPolicy.coverOpacity(progress: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(ReaderTransitionPolicy.coverOpacity(progress: 1), 0, accuracy: 0.0001)
    }

    func testCornerRadiusCollapsesOnOpen() {
        XCTAssertEqual(ReaderTransitionPolicy.cornerRadius(progress: 0, compact: 12, full: 0), 12)
        XCTAssertEqual(ReaderTransitionPolicy.cornerRadius(progress: 1, compact: 12, full: 0), 0)
    }
}
