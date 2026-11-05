import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderPageHostingTests: XCTestCase {
    private struct Page: Identifiable { let id: Int }

    func testReservingDistantCurlControllersDoesNotMountTheirSwiftUIPages() throws {
        let reader = PageCurlReaderView(pages: (0..<14).map { Page(id: $0) }, contentRevision: "fixture",
            currentPageIndex: .constant(0), pageBackgroundColor: .white, userInterfaceStyle: .light) { page in
            Text("Page \(page.id)")
        }
        let coordinator = reader.makeCoordinator()
        let reserved = (1..<14).compactMap { coordinator.reservePageController(at: $0) }
        XCTAssertEqual(reserved.count, 13)
        XCTAssertTrue(reserved.allSatisfy { !$0.isViewLoaded },
                      "A reserved controller must not silently build a distant page's hosting tree")
        let next = coordinator.viewController(at: 1)
        XCTAssertTrue(next === reserved[0], "Laziness must preserve the existing identity cache")
        XCTAssertEqual(try renderPaperPixel(next.view), [255, 255, 255, 255])
        XCTAssertTrue(next.view.isOpaque)
        XCTAssertEqual(next.overrideUserInterfaceStyle, .light)
        XCTAssertTrue(reserved.dropFirst().allSatisfy { !$0.isViewLoaded })
    }

    func testMountedCurlPageActuallyRendersNonDefaultPaperInDarkSystemAppearance() throws {
        let paper = UIColor(red: 224.0 / 255, green: 192.0 / 255, blue: 136.0 / 255, alpha: 1)
        let reader = PageCurlReaderView(pages: [Page(id: 0)], contentRevision: "warm-paper",
            currentPageIndex: .constant(0), pageBackgroundColor: paper, userInterfaceStyle: .dark) { _ in
            Color.clear
        }
        let page = reader.makeCoordinator().viewController(at: 0)
        XCTAssertEqual(try renderPaperPixel(page.view), [224, 192, 136, 255],
                       "The actual opaque page must not fall back to the system light/dark background")
    }

    func testWallpaperPageRetainsItsTransparentSurfaceWhenMountedOnDemand() {
        let reader = PageCurlReaderView(pages: [Page(id: 0)], contentRevision: "wallpaper",
            currentPageIndex: .constant(0), pageBackgroundColor: nil, userInterfaceStyle: .dark) { _ in
            Text("Wallpaper")
        }
        let coordinator = reader.makeCoordinator()
        XCTAssertEqual(coordinator.reservePageController(at: 0)?.isViewLoaded, false)
        let page = coordinator.viewController(at: 0)
        XCTAssertEqual(page.view.backgroundColor, .clear)
        XCTAssertFalse(page.view.isOpaque)
        XCTAssertEqual(page.overrideUserInterfaceStyle, .dark)
    }

    private func renderPaperPixel(_ view: UIView) throws -> [UInt8] {
        view.frame = CGRect(x: 0, y: 0, width: 80, height: 120)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        var rgba = [UInt8](repeating: 0, count: 4)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: -4, y: -4)
            view.layer.render(in: context)
        }
        return rgba
    }
}
