import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderPageHostingTests: XCTestCase {
    private struct Page: Identifiable { let id: Int }

    func testReservingDistantCurlControllersDoesNotMountTheirSwiftUIPages() {
        let reader = PageCurlReaderView(pages: (0..<14).map { Page(id: $0) }, contentRevision: "fixture",
            currentPageIndex: .constant(0), pageBackgroundColor: .white, userInterfaceStyle: .light) { page in
            Text("Page \(page.id)")
        }
        let coordinator = reader.makeCoordinator()
        let reserved = (1..<14).map { coordinator.viewController(at: $0) }
        XCTAssertTrue(reserved.allSatisfy { !$0.isViewLoaded },
                      "A reserved controller must not silently build a distant page's hosting tree")
        let next = coordinator.viewController(at: 1)
        XCTAssertTrue(next === reserved[0], "Laziness must preserve the existing identity cache")
        next.loadViewIfNeeded()
        XCTAssertEqual(next.view.backgroundColor, .white)
        XCTAssertTrue(next.view.isOpaque)
        XCTAssertEqual(next.overrideUserInterfaceStyle, .light)
        XCTAssertTrue(reserved.dropFirst().allSatisfy { !$0.isViewLoaded })
    }

    func testWallpaperPageRetainsItsTransparentSurfaceWhenMountedOnDemand() {
        let reader = PageCurlReaderView(pages: [Page(id: 0)], contentRevision: "wallpaper",
            currentPageIndex: .constant(0), pageBackgroundColor: nil, userInterfaceStyle: .dark) { _ in
            Text("Wallpaper")
        }
        let page = reader.makeCoordinator().viewController(at: 0)
        XCTAssertFalse(page.isViewLoaded)
        page.loadViewIfNeeded()
        XCTAssertEqual(page.view.backgroundColor, .clear)
        XCTAssertFalse(page.view.isOpaque)
        XCTAssertEqual(page.overrideUserInterfaceStyle, .dark)
    }
}
