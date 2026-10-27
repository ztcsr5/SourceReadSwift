import CoreGraphics
import XCTest
@testable import SourceReadSwift

final class ReaderSafeAreaResolverTests: XCTestCase {
    private func resolve(
        _ width: CGFloat,
        _ height: CGFloat,
        windowTop: CGFloat = 0,
        windowBottom: CGFloat = 0,
        statusBarHeight: CGFloat = 0
    ) -> ReaderSafeAreaResolver.Insets {
        ReaderSafeAreaResolver.resolve(
            windowTop: windowTop,
            windowBottom: windowBottom,
            statusBarHeight: statusBarHeight,
            screenSize: CGSize(width: width, height: height)
        )
    }

    /// LiveContainer 等容器把窗口安全区上报为 0 时，必须能从屏幕尺寸兜底，
    /// 否则页眉会压在状态栏下面（v1.0.60 实测截图）。
    func testDynamicIslandFallbackWhenWindowInsetsAreZero() {
        let insets = resolve(393, 852)
        XCTAssertEqual(insets.top, 59, accuracy: 0.01)
        XCTAssertEqual(insets.bottom, 34, accuracy: 0.01)
    }

    func testNotchFallbackFor390x844() {
        let insets = resolve(390, 844)
        XCTAssertEqual(insets.top, 47, accuracy: 0.01)
        XCTAssertEqual(insets.bottom, 34, accuracy: 0.01)
    }

    func testLargeNotchFallbackFor428x926() {
        let insets = resolve(428, 926)
        XCTAssertEqual(insets.top, 47, accuracy: 0.01)
        XCTAssertEqual(insets.bottom, 34, accuracy: 0.01)
    }

    func testMaxDynamicIslandFallbackFor430x932() {
        let insets = resolve(430, 932)
        XCTAssertEqual(insets.top, 59, accuracy: 0.01)
        XCTAssertEqual(insets.bottom, 34, accuracy: 0.01)
    }

    func testOlderNotchFallbackFor414x896() {
        let insets = resolve(414, 896)
        XCTAssertEqual(insets.top, 44, accuracy: 0.01)
        XCTAssertEqual(insets.bottom, 34, accuracy: 0.01)
    }

    func testMiniFallbackFor375x812() {
        let insets = resolve(375, 812)
        XCTAssertEqual(insets.top, 50, accuracy: 0.01)
    }

    func testHomeButtonDeviceHasNoBottomInset() {
        let insets = resolve(375, 667)
        XCTAssertEqual(insets.top, 20, accuracy: 0.01)
        XCTAssertEqual(insets.bottom, 0, accuracy: 0.01)
    }

    func testWindowInsetsWinOverFallback() {
        let insets = resolve(393, 852, windowTop: 59, windowBottom: 34)
        XCTAssertEqual(insets.top, 59, accuracy: 0.01)
        XCTAssertEqual(insets.bottom, 34, accuracy: 0.01)
    }

    func testStatusBarHeightUsedWhenWindowInsetsAreZero() {
        let insets = resolve(390, 844, statusBarHeight: 44)
        XCTAssertEqual(insets.top, 44, accuracy: 0.01)
        XCTAssertEqual(insets.bottom, 34, accuracy: 0.01)
    }
    func testLandscapeFallbackDoesNotInventTopInset() {
        let insets = resolve(844, 390)
        XCTAssertEqual(insets.top, 0, accuracy: 0.01)
    }
}
