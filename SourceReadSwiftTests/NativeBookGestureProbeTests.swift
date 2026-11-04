#if DEBUG
import UIKit
import XCTest
@testable import SourceReadSwift

final class NativeBookGestureProbeTests: XCTestCase {
    @MainActor func testFindsNestedNavigationButNeverDocumentScrolling() {
        let root = UIView(), nested = UIView(), deeper = UIView()
        root.addSubview(nested); nested.addSubview(deeper)
        let native = UIPanGestureRecognizer()
        deeper.addGestureRecognizer(native)
        let scrolling = UIScrollView()
        root.addSubview(scrolling)
        scrolling.addGestureRecognizer(UIPanGestureRecognizer())
        let document = UIView()
        document.accessibilityIdentifier = "reader.webScrollSurface"
        root.addSubview(document)
        document.addGestureRecognizer(UIPanGestureRecognizer())
        let fallback = UIPanGestureRecognizer()
        fallback.name = "reader.menuSwipeExit"
        root.addGestureRecognizer(fallback)
        root.addGestureRecognizer(UITapGestureRecognizer())
        let observed = NativeBookGestureProbe.collect(in: root).map { ObjectIdentifier($0) }
        XCTAssertEqual(observed, [ObjectIdentifier(native)])
    }

    @MainActor func testHasABoundedContainerWalk() {
        let root = UIView()
        var leaf = root
        for _ in 0..<300 {
            let child = UIView(); leaf.addSubview(child); leaf = child
        }
        leaf.addGestureRecognizer(UIPanGestureRecognizer())
        XCTAssertTrue(NativeBookGestureProbe.collect(in: root).isEmpty)
    }
}
#endif
