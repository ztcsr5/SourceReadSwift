import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ComicStripLayoutTests: XCTestCase {
    func testPagesArrivingWithinTheSameChapterReplaceTheEmptyFooter() throws {
        let fixture = ComicStripLayoutFixture(requests: [])
        defer { fixture.close() }
        XCTAssertEqual(fixture.strip.numberOfItems(inSection: 0), 1)
        let requests = (0..<3).map {
            ComicImageRequest(url: "file:///comic-late-pages/\($0).png", headers: [:])
        }
        let populated = ComicStripReaderView(requests: requests, contentKey: "layout-fixture",
            viewportWidth: 390, targetPage: nil, footerTitle: "目录末尾",
            canActivateFooter: false, reducesMotion: true, onVisiblePage: { _ in },
            onTargetApplied: {}, onTap: {}, onRefreshAddresses: {}, onFooter: {})
        fixture.coordinator.update(populated)
        fixture.strip.layoutIfNeeded()
        XCTAssertEqual(fixture.strip.numberOfItems(inSection: 0), 4)
        XCTAssertTrue(fixture.strip.cellForItem(at: IndexPath(item: 0, section: 0)) is ComicStripImageCell,
                      "A same-chapter update must replace the empty footer with the first page")
    }

    func testLongChapterRecyclesDecodedImageViewsAndCancelsAllDepartingSubscribers() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let picture = UIGraphicsImageRenderer(size: CGSize(width: 390, height: 1000)).image { renderer in
            UIColor.white.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 390, height: 1000))
        }
        let bytes = try XCTUnwrap(picture.pngData())
        let requests = try (0..<240).map { page -> ComicImageRequest in
            let file = root.appendingPathComponent("\(page).png")
            try bytes.write(to: file)
            return ComicImageRequest(url: file.absoluteString, headers: [:])
        }
        let fixture = ComicStripLayoutFixture(requests: requests)
        defer { fixture.close() }
        fixture.coordinator.collectionView(fixture.strip,
            willDisplay: try XCTUnwrap(fixture.strip.cellForItem(at: IndexPath(item: 0, section: 0))),
            forItemAt: IndexPath(item: 0, section: 0))
        func firstBitmapExists() -> Bool {
            fixture.strip.cellForItem(at: IndexPath(item: 0, section: 0))?.contentView.subviews
                .compactMap { $0 as? ComicZoomScrollView }.first?.artwork.image != nil
        }
        for _ in 0..<200 {
            if firstBitmapExists() { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(firstBitmapExists(), "The stress path must render decoded files, not only placeholders")
        for page in stride(from: 0, to: requests.count, by: 3) {
            let frame = try XCTUnwrap(fixture.strip.layoutAttributesForItem(at: IndexPath(item: page, section: 0))).frame
            fixture.strip.setContentOffset(CGPoint(x: 0, y: frame.minY), animated: false)
            fixture.strip.layoutIfNeeded()
            fixture.coordinator.scrollViewDidScroll(fixture.strip)
            await Task.yield()
            XCTAssertLessThanOrEqual(fixture.strip.visibleCells.count, 8)
            XCTAssertLessThanOrEqual(fixture.strip.subviews.filter { $0 is UICollectionViewCell }.count, 24,
                                     "Decoded page views must not accumulate with chapter length")
        }
        fixture.coordinator.cancelLoads()
        for _ in 0..<200 {
            if requests.allSatisfy({ request in
                guard let address = URL(string: request.url) else { return false }
                return RemoteImageLoader.shared.comicSubscriberCount(for: address, headers: [:],
                    maxPixelSize: ComicPagePositionPolicy.maxImagePixels) == 0
            }) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        for request in requests {
            let address = try XCTUnwrap(URL(string: request.url))
            XCTAssertEqual(RemoteImageLoader.shared.comicSubscriberCount(for: address, headers: [:],
                maxPixelSize: ComicPagePositionPolicy.maxImagePixels), 0)
        }
    }

    func testSizingUsesTheFullImageAspectRatioWithoutCroppingLongStrips() {
        XCTAssertEqual(ComicStripGeometry.height(for: CGSize(width: 1000, height: 8000), width: 390), 3120)
        XCTAssertEqual(ComicStripGeometry.height(for: CGSize(width: 2000, height: 500), width: 390), 97.5)
        XCTAssertEqual(ComicStripGeometry.height(for: nil, width: 390), 320)
        XCTAssertEqual(ComicStripGeometry.height(for: CGSize(width: 0, height: 100), width: 390), 320)
    }

    func testUpstreamImageHeightWaitsForInertiaAndRestoresTheSameReadingLine() throws {
        let fixture = ComicStripLayoutFixture()
        defer { fixture.close() }
        fixture.strip.setContentOffset(CGPoint(x: 0, y: 760), animated: false)
        fixture.strip.layoutIfNeeded()
        let chapterLine = IndexPath(item: 2, section: 0)
        let before = try XCTUnwrap(fixture.strip.layoutAttributesForItem(at: chapterLine)).frame
        let offset = fixture.strip.contentOffset.y - before.minY
        fixture.strip.simulatesInertia = true
        fixture.coordinator.acceptSize(CGSize(width: 390, height: 1000), for: 0)
        fixture.strip.layoutIfNeeded()
        XCTAssertEqual(fixture.strip.layoutAttributesForItem(at: chapterLine)?.frame, before)
        XCTAssertEqual(fixture.coordinator.deferredSizeCount, 1)
        XCTAssertEqual(fixture.strip.contentOffset.y, 760, accuracy: 1)
        fixture.strip.simulatesInertia = false
        fixture.coordinator.scrollViewDidEndDecelerating(fixture.strip)
        let after = try XCTUnwrap(fixture.strip.layoutAttributesForItem(at: chapterLine)).frame
        XCTAssertEqual(after.minY - before.minY, 680, accuracy: 1)
        XCTAssertEqual(fixture.strip.contentOffset.y - after.minY, offset, accuracy: 1)
    }

    func testReverseScrollChoosesTheCurrentAnchorWhenDeferredImagesSettle() throws {
        let fixture = ComicStripLayoutFixture()
        defer { fixture.close() }
        fixture.strip.setContentOffset(CGPoint(x: 0, y: 1080), animated: false)
        fixture.strip.simulatesInertia = true
        fixture.coordinator.acceptSize(CGSize(width: 390, height: 1800), for: 0)
        fixture.strip.setContentOffset(CGPoint(x: 0, y: 360), animated: false)
        fixture.strip.layoutIfNeeded()
        fixture.strip.simulatesInertia = false
        fixture.coordinator.scrollViewDidEndDecelerating(fixture.strip)
        let reversedPage = try XCTUnwrap(fixture.strip.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))).frame
        XCTAssertEqual(fixture.strip.contentOffset.y - reversedPage.minY, 40, accuracy: 1)
    }

    func testResumeKeepsThePageFractionWhenTheActualLongImageArrives() async throws {
        let fixture = ComicStripLayoutFixture()
        defer { fixture.close() }
        let applied = expectation(description: "Approximate target mounted")
        fixture.source.onTargetApplied = { applied.fulfill() }
        fixture.source.targetPage = 2
        fixture.source.targetFraction = 0.6
        fixture.coordinator.update(fixture.source)
        await fulfillment(of: [applied], timeout: 2)
        fixture.source.targetPage = nil
        fixture.coordinator.update(fixture.source)
        fixture.coordinator.acceptSize(CGSize(width: 390, height: 1800), for: 2)
        let frame = try XCTUnwrap(fixture.strip.layoutAttributesForItem(at: IndexPath(item: 2, section: 0))).frame
        XCTAssertEqual(fixture.strip.contentOffset.y - frame.minY, frame.height * 0.6, accuracy: 1)
    }

    func testUserDragCancelsPendingFractionalResumeBeforeLateImageSizing() async throws {
        let fixture = ComicStripLayoutFixture()
        defer { fixture.close() }
        let applied = expectation(description: "Approximate target mounted")
        fixture.source.onTargetApplied = { applied.fulfill() }
        fixture.source.targetPage = 2
        fixture.source.targetFraction = 0.6
        fixture.coordinator.update(fixture.source)
        await fulfillment(of: [applied], timeout: 2)
        fixture.source.onTargetApplied = {}
        fixture.source.targetPage = nil
        fixture.coordinator.update(fixture.source)
        fixture.coordinator.scrollViewWillBeginDragging(fixture.strip)
        fixture.strip.setContentOffset(CGPoint(x: 0, y: 40), animated: false)
        XCTAssertEqual(fixture.strip.contentOffset.y, 40, accuracy: 1, "Reversal must precede the late image callback")
        fixture.coordinator.acceptSize(CGSize(width: 390, height: 1800), for: 2)
        XCTAssertEqual(fixture.strip.contentOffset.y, 40, accuracy: 1)
    }
}

@MainActor
private final class ComicStripLayoutFixture {
    let strip: SimulatedComicStrip
    let coordinator: ComicStripReaderView.Coordinator
    private let window: UIWindow
    private let previous: UIWindow?
    var source: ComicStripReaderView

    init(requests: [ComicImageRequest]? = nil) {
        let source = ComicStripReaderView(
            requests: requests ?? (0..<8).map { ComicImageRequest(url: "file:///nonexistent-comic-layout-fixture/\($0)", headers: [:]) },
            contentKey: "layout-fixture", viewportWidth: 390, targetPage: nil, footerTitle: "目录末尾",
            canActivateFooter: false, reducesMotion: true, onVisiblePage: { _ in }, onTargetApplied: {},
            onTap: {}, onRefreshAddresses: {}, onFooter: {})
        self.source = source
        coordinator = ComicStripReaderView.Coordinator(view: source)
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        strip = SimulatedComicStrip(frame: CGRect(x: 0, y: 0, width: 390, height: 760), collectionViewLayout: layout)
        strip.contentInsetAdjustmentBehavior = .never
        strip.register(ComicStripImageCell.self, forCellWithReuseIdentifier: "page")
        strip.register(ComicStripFooterCell.self, forCellWithReuseIdentifier: "footer")
        coordinator.strip = strip
        strip.dataSource = coordinator
        strip.delegate = coordinator
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        previous = scene?.windows.first(where: \.isKeyWindow)
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController()
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.addSubview(strip)
        strip.reloadData()
        strip.layoutIfNeeded()
    }

    func close() {
        coordinator.cancelLoads()
        strip.delegate = nil
        strip.dataSource = nil
        window.isHidden = true
        previous?.makeKey()
    }
}

private final class SimulatedComicStrip: UICollectionView {
    var simulatesInertia = false
    override var isDecelerating: Bool { simulatesInertia || super.isDecelerating }
}
