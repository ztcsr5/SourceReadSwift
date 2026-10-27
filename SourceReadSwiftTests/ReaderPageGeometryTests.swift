import XCTest
import UIKit
@testable import SourceReadSwift

final class ReaderPageGeometryTests: XCTestCase {
    private func geometry(
        width: CGFloat = 390,
        height: CGFloat = 844,
        safeTop: CGFloat = 50,
        safeBottom: CGFloat = 34,
        margin: CGFloat = 21,
        layout: ReaderPageChromeLayout = .header,
        extends: Bool = false
    ) -> ReaderPageGeometry {
        ReaderPageGeometry(
            viewportSize: CGSize(width: width, height: height),
            safeTop: safeTop,
            safeBottom: safeBottom,
            horizontalMargin: margin,
            chromeLayout: layout,
            contentExtendsIntoChrome: extends
        )
    }

    /// 390×844pt / safeTop 50 是竞品截图的量测基准：
    /// 页眉墨迹 50–61、正文顶 84.3、正文底 819、页码底 831.7。
    func testHeaderLayoutMatchesCompetitorScreenshot() {
        let geo = geometry()
        XCTAssertEqual(geo.contentWidth, 348, accuracy: 0.01)
        XCTAssertEqual(geo.bodyTop, 84, accuracy: 0.01)
        XCTAssertEqual(geo.footerTop, 813, accuracy: 0.01)
        XCTAssertEqual(geo.bodyBottom, 809, accuracy: 0.01)
        XCTAssertEqual(geo.contentHeight, 725, accuracy: 0.01)
        XCTAssertEqual(geo.headerRect.minX, 21, accuracy: 0.01)
        XCTAssertEqual(geo.headerRect.minY, 52, accuracy: 0.01)
        XCTAssertTrue(geo.showsHeader)
    }

    func testDynamicIslandViewportKeepsBodyBelowSafeArea() {
        let geo = geometry(width: 393, height: 852, safeTop: 59, safeBottom: 34)
        XCTAssertEqual(geo.bodyTop, 93, accuracy: 0.01)
        XCTAssertEqual(geo.footerTop, 821, accuracy: 0.01)
        XCTAssertEqual(geo.bodyBottom, 817, accuracy: 0.01)
        XCTAssertEqual(geo.contentHeight, 724, accuracy: 0.01)
    }

    func testInlineAndHiddenLayoutsDoNotReserveHeaderBand() {
        let inline = geometry(layout: .inline)
        XCTAssertEqual(inline.bodyTop, 58, accuracy: 0.01)
        XCTAssertFalse(inline.showsHeader)
        XCTAssertGreaterThan(inline.contentHeight, geometry().contentHeight)

        let hidden = geometry(layout: .hidden)
        XCTAssertEqual(hidden.bodyTop, 62, accuracy: 0.01)
        XCTAssertFalse(hidden.showsHeader)
    }

    func testContentExtensionUsesHeaderFooterAsOverlay() {
        let geo = geometry(extends: true)
        XCTAssertEqual(geo.bodyTop, 58, accuracy: 0.01)
        XCTAssertEqual(geo.bodyBottom, 834, accuracy: 0.01)
        XCTAssertEqual(geo.contentHeight, 776, accuracy: 0.01)
    }

    func testHorizontalMarginClampsOnNarrowViewports() {
        let geo = geometry(width: 200, height: 600, margin: 200)
        XCTAssertLessThanOrEqual(geo.contentWidth, 80.01)
        XCTAssertGreaterThan(geo.contentWidth, 0)
    }

    /// UIPageViewController 子控制器被安全区再内缩时：原点 59pt、高度 793pt。
    /// 此时页面内部不能再补一次 safeTop，否则正文会被推下两份刘海高度。
    func testInsetPageContainerDoesNotDoubleApplySafeArea() {
        let metrics = ReaderPageContainerMetrics(
            size: CGSize(width: 393, height: 793),
            globalMinY: 59,
            rootViewportHeight: 852,
            rootSafeTop: 59,
            rootSafeBottom: 34
        )
        XCTAssertEqual(metrics.resolvedSafeTop, 0, accuracy: 0.01)
        XCTAssertEqual(metrics.resolvedSafeBottom, 34, accuracy: 0.01)

        let geo = metrics.geometry(
            horizontalMargin: 21,
            chromeLayout: .header,
            contentExtendsIntoChrome: false
        )
        XCTAssertEqual(geo.bodyTop, 34, accuracy: 0.01)
        XCTAssertEqual(geo.footerTop, 762, accuracy: 0.01)
        XCTAssertEqual(geo.bodyBottom, 758, accuracy: 0.01)
        XCTAssertEqual(geo.contentHeight, 724, accuracy: 0.01)
    }

    func testFullBleedPageContainerUsesWindowSafeInsets() {
        let metrics = ReaderPageContainerMetrics(
            size: CGSize(width: 393, height: 852),
            globalMinY: 0,
            rootViewportHeight: 852,
            rootSafeTop: 59,
            rootSafeBottom: 34
        )
        XCTAssertEqual(metrics.resolvedSafeTop, 59, accuracy: 0.01)
        XCTAssertEqual(metrics.resolvedSafeBottom, 34, accuracy: 0.01)
        XCTAssertEqual(
            metrics.geometry(
                horizontalMargin: 21,
                chromeLayout: .header,
                contentExtendsIntoChrome: false
            ).bodyTop,
            93,
            accuracy: 0.01
        )
    }

    func testInvalidMetricsFallBackToRootInsets() {
        let metrics = ReaderPageContainerMetrics(
            size: .zero,
            globalMinY: 0,
            rootViewportHeight: 852,
            rootSafeTop: 59,
            rootSafeBottom: 34
        )
        XCTAssertFalse(metrics.isValid)
        XCTAssertEqual(metrics.resolvedSafeTop, 59, accuracy: 0.01)
        XCTAssertEqual(metrics.resolvedSafeBottom, 34, accuracy: 0.01)
    }

    func testScrollFooterBandOnlyReservesWhenFooterAtBottom() {
        XCTAssertEqual(ReaderPageChrome.scrollFooterReservedHeight(statusPosition: "bottom"), 40, accuracy: 0.01)
        XCTAssertEqual(ReaderPageChrome.scrollFooterReservedHeight(statusPosition: "both"), 40, accuracy: 0.01)
        XCTAssertEqual(ReaderPageChrome.scrollFooterReservedHeight(statusPosition: "top"), 0, accuracy: 0.01)
        XCTAssertEqual(ReaderPageChrome.scrollFooterReservedHeight(statusPosition: "none"), 0, accuracy: 0.01)
    }
}
