import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderCurlSurfaceTests: XCTestCase {
    func testFoldStartsFlatAndEndsEntirelyOutsideTheViewport() {
        for width: CGFloat in [320, 390, 844] {
            for step in 0...24 {
                let x = width * CGFloat(step) / 24
                let start = ReaderCurlSurface.foldPosition(x: x, width: width, progress: 0)
                let end = ReaderCurlSurface.foldPosition(x: x, width: width, progress: 1)
                XCTAssertEqual(start.x, x, accuracy: 0.001)
                XCTAssertEqual(start.depth, 0)
                XCTAssertEqual(end.x, -x, accuracy: 0.001)
                XCTAssertEqual(end.depth, 0, accuracy: 0.001)
            }
        }
    }

    func testFoldIsContinuousAtTheFlatAndReverseSegments() {
        let width: CGFloat = 390
        let progress: CGFloat = 0.5
        let fold = width * (1 - progress)
        let radius = width * 0.1
        for x in [fold, fold + .pi * radius] {
            let before = ReaderCurlSurface.foldPosition(x: x - 0.001, width: width, progress: progress)
            let after = ReaderCurlSurface.foldPosition(x: x + 0.001, width: width, progress: progress)
            XCTAssertLessThan(abs(before.x - after.x), 0.01)
            XCTAssertLessThan(abs(before.depth - after.depth), 0.01)
        }
    }

    func testCurlUsesFullHeightSharedBitmapAndResetsBothDirections() throws {
        for direction in [-1, 1] {
            let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let pages = (0..<3).map { index in
                let page = UIView(frame: container.bounds)
                page.backgroundColor = [.red, .green, .blue][index]
                page.accessibilityIdentifier = "p\(index)"
                container.addSubview(page)
                return page
            }
            let surface = ReaderCurlSurface()
            surface.warm(page: pages[1], key: pages[1].accessibilityIdentifier ?? "")
            surface.prepare(direction: direction, in: container, pages: pages)
            surface.apply(translation: -CGFloat(direction) * 195, in: container, pages: pages)
            let overlay = try XCTUnwrap(container.subviews.last)
            XCTAssertFalse(pages.contains(overlay))
            XCTAssertEqual(overlay.bounds, container.bounds)
            XCTAssertEqual(overlay.subviews.count, 24)
            let bitmap = try XCTUnwrap(overlay.subviews.first?.layer.contents as? CGImage)
            for strip in overlay.subviews {
                XCTAssertEqual(strip.bounds.height, 844)
                let contents = try XCTUnwrap(strip.layer.contents as? CGImage)
                XCTAssertTrue(contents === bitmap)
                XCTAssertEqual(strip.layer.contentsRect.height, 1)
            }
            XCTAssertTrue(overlay.subviews.contains { abs($0.layer.affineTransform().a - 1) > 0.01 })
            XCTAssertFalse(pages[0].isUserInteractionEnabled)
            XCTAssertTrue(pages[2].accessibilityElementsHidden)
            surface.reset(pages: pages)
            XCTAssertEqual(container.subviews.count, 3)
            XCTAssertEqual(pages[1].alpha, 1)
            XCTAssertEqual(pages[1].transform, .identity)
            XCTAssertEqual(pages[1].layer.shadowOpacity, 0)
            XCTAssertTrue(pages[1].isUserInteractionEnabled)
            XCTAssertTrue(overlay.subviews.allSatisfy { strip in
                strip.layer.opacity == 1
                    && strip.subviews.allSatisfy { $0.layer.opacity == 0 && $0.layer.backgroundColor == nil }
            })
            XCTAssertTrue(overlay.subviews.allSatisfy { $0.layer.contents == nil })
        }
    }

    func testUnwarmedApplyUsesTranslationFallbackWithoutCreatingOverlay() throws {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let pages = (0..<3).map { index in
            let page = UIView(frame: container.bounds)
            page.accessibilityIdentifier = "cold-\(index)"
            container.addSubview(page)
            return page
        }
        let surface = ReaderCurlSurface()
        pages[1].layer.shadowOpacity = 0.32
        pages[1].layer.transform = CATransform3DRotate(CATransform3DIdentity, 0.2, 0, 1, 0)
        surface.apply(translation: -120, in: container, pages: pages)

        XCTAssertEqual(container.subviews.count, 3)
        XCTAssertEqual(pages[1].transform, CGAffineTransform(translationX: -120, y: 0))
        XCTAssertEqual(pages[2].transform, CGAffineTransform(translationX: 270, y: 0))
        XCTAssertEqual(pages[1].alpha, 1)
        XCTAssertEqual(pages[1].layer.shadowOpacity, 0)
        XCTAssertEqual(pages[1].layer.affineTransform(), pages[1].transform)
        XCTAssertTrue(CATransform3DIsAffine(pages[1].layer.transform))
        XCTAssertFalse(pages[1].accessibilityElementsHidden)

        surface.reset(pages: pages)
        XCTAssertEqual(pages[1].transform, .identity)
        XCTAssertEqual(pages[2].transform, .identity)
    }
}
