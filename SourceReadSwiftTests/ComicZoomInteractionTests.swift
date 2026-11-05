import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ComicZoomInteractionTests: XCTestCase {
    func testZoomSuspendsOnlyThePagingAncestorAndRestoresItsOriginalState() {
        for wasEnabled in [true, false] {
            let pager = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            pager.isPagingEnabled = true
            pager.isScrollEnabled = wasEnabled
            let container = UIScrollView(frame: pager.bounds)
            let zoom = ComicZoomScrollView(frame: pager.bounds)
            pager.addSubview(container)
            container.addSubview(zoom)
            let coordinator = ComicPageZoomView.Coordinator()
            var zoomStates: [Bool] = []
            coordinator.onZoomChanged = { zoomStates.append($0) }

            coordinator.scrollViewWillBeginZooming(zoom, with: zoom.artwork)
            XCTAssertFalse(pager.isScrollEnabled)
            XCTAssertTrue(container.isScrollEnabled, "Non-paging ancestors retain their own scrolling")
            coordinator.scrollViewDidEndZooming(zoom, with: zoom.artwork, atScale: 2)
            XCTAssertFalse(pager.isScrollEnabled, "A completed pinch at 2x still owns panning")
            coordinator.scrollViewWillBeginZooming(zoom, with: zoom.artwork)
            coordinator.scrollViewDidEndZooming(zoom, with: zoom.artwork, atScale: 1)
            XCTAssertEqual(pager.isScrollEnabled, wasEnabled, "Repeated zoom must not overwrite the original state")
            XCTAssertEqual(zoomStates, [true, true, true, false])
        }
    }

    func testRemovingAZoomedPageRestoresPagingWithoutWaitingForAnotherPinch() {
        let pager = UIScrollView()
        pager.isPagingEnabled = true
        let zoom = ComicZoomScrollView()
        pager.addSubview(zoom)
        let coordinator = ComicPageZoomView.Coordinator()
        zoom.delegate = coordinator
        coordinator.scrollViewWillBeginZooming(zoom, with: zoom.artwork)
        XCTAssertFalse(pager.isScrollEnabled)
        ComicPageZoomView.dismantleUIView(zoom, coordinator: coordinator)
        XCTAssertTrue(pager.isScrollEnabled)
        XCTAssertNil(zoom.delegate)
        coordinator.restoreParentPaging()
        XCTAssertTrue(pager.isScrollEnabled, "Late cleanup must remain idempotent")
    }

    func testPinchAtFitKeepsPagingSuspendedUntilTheGestureActuallyEnds() {
        let pager = UIScrollView()
        pager.isPagingEnabled = true
        let zoom = ComicZoomScrollView()
        pager.addSubview(zoom)
        let coordinator = ComicPageZoomView.Coordinator()
        coordinator.scrollViewWillBeginZooming(zoom, with: zoom.artwork)
        coordinator.scrollViewDidZoom(zoom)
        XCTAssertFalse(pager.isScrollEnabled, "The first pinch callback may still report scale 1")
        coordinator.scrollViewDidEndZooming(zoom, with: zoom.artwork, atScale: 1)
        XCTAssertTrue(pager.isScrollEnabled)
    }

    func testStripZoomDoesNotOverrideItsNonPagingCollectionView() {
        let strip = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let zoom = ComicZoomScrollView()
        strip.addSubview(zoom)
        let coordinator = ComicPageZoomView.Coordinator()
        coordinator.scrollViewWillBeginZooming(zoom, with: zoom.artwork)
        XCTAssertTrue(strip.isScrollEnabled, "The strip coordinator, not the horizontal pager guard, owns this state")
        strip.isScrollEnabled = false
        coordinator.scrollViewDidEndZooming(zoom, with: zoom.artwork, atScale: 1)
        XCTAssertFalse(strip.isScrollEnabled)
    }

    func testReusedPageReleasesItsBitmapAndReturnsToFitWithoutEnablingPan() {
        let zoom = ComicZoomScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let coordinator = ComicPageZoomView.Coordinator()
        zoom.delegate = coordinator
        let image = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 960)).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 390, height: 960))
        }
        zoom.setImage(image)
        zoom.layoutIfNeeded()
        zoom.setZoomScale(2, animated: false)
        coordinator.scrollViewDidZoom(zoom)
        XCTAssertTrue(zoom.panGestureRecognizer.isEnabled)
        zoom.resetImage()
        XCTAssertNil(zoom.artwork.image)
        XCTAssertEqual(zoom.zoomScale, 1, accuracy: 0.01)
        XCTAssertFalse(zoom.panGestureRecognizer.isEnabled)
    }
}
