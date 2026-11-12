import XCTest
import UIKit
@testable import SourceReadSwift

@MainActor
final class ReaderZoomSourceTests: XCTestCase {
    func testDetachedSourceOnlyBelongsToTheWindowWhereItWasResolved() {
        let sources = ReaderZoomSources()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let other = UIWindow(frame: window.bounds)
        let container = UIView(frame: window.bounds)
        let cover = UIView(frame: CGRect(x: 20, y: 100, width: 100, height: 140))
        window.addSubview(container)
        container.addSubview(cover)
        sources.register(cover, id: "continue|book")
        XCTAssertTrue(sources.source(id: "continue|book", window: window) === cover)
        container.removeFromSuperview()
        sources.register(cover, id: "continue|book")
        XCTAssertTrue(sources.source(id: "continue|book", window: window) === cover)
        XCTAssertNil(sources.source(id: "continue|book", window: other))
    }

    func testVisibleSourceWinsOverAnOlderRetainedCopyAndPlacementsStayDistinct() {
        let sources = ReaderZoomSources()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let container = UIView(frame: window.bounds)
        let earlier = UIView(frame: CGRect(x: 20, y: 100, width: 100, height: 140))
        window.addSubview(container)
        container.addSubview(earlier)
        sources.register(earlier, id: "continue|book")
        _ = sources.source(id: "continue|book", window: window)
        container.removeFromSuperview()
        let visible = UIView(frame: earlier.frame)
        window.addSubview(visible)
        sources.register(visible, id: "continue|book")
        let grid = UIView(frame: CGRect(x: 200, y: 300, width: 80, height: 110))
        window.addSubview(grid)
        sources.register(grid, id: "grid|book")
        XCTAssertTrue(sources.source(id: "continue|book", window: window) === visible)
        XCTAssertTrue(sources.source(id: "grid|book", window: window) === grid)
        visible.frame.origin.y = 1200
        XCTAssertTrue(sources.source(id: "continue|book", window: window) === earlier)
    }
}
