import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ComicStripLayoutTests: XCTestCase {
    func testCancellingBeforeDeferredDisplayAndResumeCallbacksDoesNotRestartLoading() async {
        let probe = ComicPageLoadProbe()
        let requests = (0..<12).map {
            ComicImageRequest(url: "https://comic-cancellation.invalid/\(UUID().uuidString)/\($0).png", headers: [:])
        }
        let fixture = ComicStripLayoutFixture(requests: requests, imageLoader: { _, request, _ in
            let page = Int(URL(string: request.url)?.deletingPathExtension().lastPathComponent ?? "") ?? -1
            await probe.load(page)
            return .failure(.cancelled)
        })
        defer { fixture.close(); probe.releaseAll() }
        fixture.source.targetPage = 3
        fixture.coordinator.update(fixture.source)
        fixture.coordinator.cancelLoads()
        let callbacksDrained = expectation(description: "Deferred display callbacks drained")
        DispatchQueue.main.async { callbacksDrained.fulfill() }
        await fulfillment(of: [callbacksDrained], timeout: 2)
        XCTAssertTrue(probe.started.isEmpty, "Cancelling the reader must also retire UI callbacks waiting on the main queue")
    }

    func testFailedSpeculativePageGetsAForegroundAttemptWhenScrolledIntoView() async throws {
        var attempts: [Int: Int] = [:]
        let requests = (0..<12).map {
            ComicImageRequest(url: "https://comic-retry.invalid/\(UUID().uuidString)/\($0).png", headers: [:])
        }
        let fixture = ComicStripLayoutFixture(requests: requests, imageLoader: { _, request, _ in
            let page = Int(URL(string: request.url)?.deletingPathExtension().lastPathComponent ?? "") ?? -1
            attempts[page, default: 0] += 1
            return .failure(.timedOut)
        })
        defer { fixture.close() }
        for _ in 0..<200 {
            if attempts[3] == 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(attempts[3], 1, "The page must first fail outside the viewport")
        let frame = try XCTUnwrap(fixture.strip.layoutAttributesForItem(at: IndexPath(item: 3, section: 0))).frame
        fixture.strip.setContentOffset(CGPoint(x: 0, y: frame.minY), animated: false)
        fixture.strip.layoutIfNeeded()
        fixture.coordinator.scrollViewDidScroll(fixture.strip)
        for _ in 0..<200 {
            if (attempts[3] ?? 0) > 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(attempts[3], 2, "A speculative timeout must not leave a permanent failure on a page the reader has not seen")
    }

    func testResumeStartsAheadOfTheViewportBeforeTheTargetImageHasLoaded() async throws {
        let probe = ComicPageLoadProbe()
        let requests = (0..<12).map {
            ComicImageRequest(url: "https://comic-prefetch.invalid/\(UUID().uuidString)/\($0).png", headers: [:])
        }
        let fixture = ComicStripLayoutFixture(requests: requests, imageLoader: { _, request, _ in
            let page = Int(URL(string: request.url)?.deletingPathExtension().lastPathComponent ?? "") ?? -1
            await probe.load(page)
            return .failure(.cancelled)
        })
        defer { fixture.close(); probe.releaseAll() }
        fixture.source.targetPage = 3
        fixture.coordinator.update(fixture.source)
        for _ in 0..<200 {
            if probe.started.contains(3), probe.started.contains(6) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(probe.waitingPages.contains(3), "The resume artwork is deliberately still unresolved")
        XCTAssertTrue(probe.started.contains(6), "Begin loading beyond the estimated visible pages before any image or scroll completes")
    }

    func testPagesArrivingWithinTheSameChapterReplaceTheEmptyFooter() throws {
        let fixture = ComicStripLayoutFixture(requests: [])
        defer { fixture.close() }
        XCTAssertEqual(fixture.strip.numberOfItems(inSection: 0), 1)
        let requests = (0..<3).map {
            ComicImageRequest(url: "file:///comic-late-pages/\($0).png", headers: [:])
        }
        fixture.source.snapshot = ComicStripSnapshot(chapters: [ComicStripLayoutFixture.chapter(0, requests: requests)])
        fixture.coordinator.update(fixture.source)
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
        let firstAddress = try XCTUnwrap(URL(string: requests[0].url))
        let firstCell = fixture.strip.cellForItem(at: IndexPath(item: 0, section: 0))
        let firstStatus = firstCell?.contentView.subviews.compactMap { $0 as? UIStackView }.first?
            .arrangedSubviews.compactMap { $0 as? UILabel }.first?.text ?? "missing"
        let firstCached = RemoteImageLoader.shared.cachedComicPage(for: firstAddress, headers: [:],
            maxPixelSize: ComicPagePositionPolicy.maxImagePixels) != nil
        let firstSubscribers = RemoteImageLoader.shared.comicSubscriberCount(for: firstAddress, headers: [:],
            maxPixelSize: ComicPagePositionPolicy.maxImagePixels)
        let firstState = "cached=\(firstCached); subscribers=\(firstSubscribers); status=\(firstStatus); "
            + "visible=\(fixture.strip.indexPathsForVisibleItems); offset=\(fixture.strip.contentOffset); "
            + "cell=\(String(describing: firstCell?.frame)); windowHidden=\(String(describing: fixture.strip.window?.isHidden)); "
            + "dragging=\(fixture.strip.isDragging); decelerating=\(fixture.strip.isDecelerating); tracking=\(fixture.strip.isTracking)"
        XCTAssertTrue(firstBitmapExists(), "The stress path must render decoded files, not only placeholders; \(firstState)")
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

    func testPrependAndAppendKeepTheSameVisibleCellAndLineAfterInertia() throws {
        let fixture = ComicStripLayoutFixture(chapterOffset: 1)
        defer { fixture.close() }
        let current = ComicStripLayoutFixture.chapter(1)
        let key = ComicStripPageKey(chapterOffset: 1, pageIndex: 1)
        let originalPath = IndexPath(item: 1, section: 0)
        fixture.strip.setContentOffset(CGPoint(x: 0, y: 380), animated: false)
        fixture.strip.layoutIfNeeded()
        let cell = try XCTUnwrap(fixture.strip.cellForItem(at: originalPath))
        let before = try XCTUnwrap(fixture.strip.layoutAttributesForItem(at: originalPath)).frame
        let line = fixture.strip.contentOffset.y - before.minY

        fixture.strip.simulatesInertia = true
        fixture.source.snapshot = ComicStripSnapshot(chapters: [ComicStripLayoutFixture.chapter(0), current,
            ComicStripLayoutFixture.chapter(2)])
        fixture.coordinator.update(fixture.source)
        XCTAssertEqual(fixture.strip.numberOfItems(inSection: 0), 9)
        XCTAssertEqual(fixture.strip.contentOffset.y, 380, accuracy: 1)

        fixture.strip.simulatesInertia = false
        fixture.coordinator.scrollViewDidEndDecelerating(fixture.strip)
        fixture.strip.layoutIfNeeded()
        let moved = try XCTUnwrap(fixture.source.snapshot.indices[key])
        let path = IndexPath(item: moved, section: 0)
        let after = try XCTUnwrap(fixture.strip.layoutAttributesForItem(at: path)).frame
        XCTAssertEqual(fixture.strip.contentOffset.y - after.minY, line, accuracy: 1)
        XCTAssertTrue(fixture.strip.cellForItem(at: path) === cell, "Splicing must not reload the active image cell")
        XCTAssertEqual(fixture.strip.numberOfItems(inSection: 0), 25)
    }
}

@MainActor
private final class ComicStripLayoutFixture {
    let strip: SimulatedComicStrip
    let coordinator: ComicStripReaderView.Coordinator
    private let window: UIWindow
    private let previous: UIWindow?
    var source: ComicStripReaderView

    init(requests: [ComicImageRequest]? = nil, chapterOffset: Int = 0,
         imageLoader: ComicStripReaderView.Coordinator.PageLoader? = nil) {
        let chapter = Self.chapter(chapterOffset, requests: requests)
        let source = ComicStripReaderView(
            snapshot: ComicStripSnapshot(chapters: [chapter]), contentKey: 1, viewport: CGSize(width: 390, height: 760),
            chapterOffset: chapterOffset, targetPage: nil, targetFraction: 0,
            footer: .init(title: "目录末尾", isEnabled: false, action: {}), display: .init(),
            reducesMotion: true, isContinuous: false, onTargetApplied: {}, onTap: {}, onRefreshAddresses: { _ in },
            onPosition: { _, _, _ in }, onApproachChapter: { _ in }, onBeginDragging: {})
        self.source = source
        coordinator = ComicStripReaderView.Coordinator(view: source, imageLoader: imageLoader)
        strip = SimulatedComicStrip(frame: CGRect(x: 0, y: 0, width: 390, height: 760),
            collectionViewLayout: ComicOffsetPreservingLayout())
        strip.contentInsetAdjustmentBehavior = .never
        coordinator.attach(to: strip)
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

    static func chapter(_ offset: Int, requests: [ComicImageRequest]? = nil) -> ComicStripChapter {
        let requests = requests ?? (0..<8).map {
            ComicImageRequest(url: "file:///nonexistent-comic-layout-fixture/\(offset)/\($0)", headers: [:])
        }
        let pages = requests.enumerated().map { ComicPage(id: $0.offset, url: $0.element.url) }
        return ComicStripChapter(offset: offset, resources: .init(offlinePages: pages), requests: requests)
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
