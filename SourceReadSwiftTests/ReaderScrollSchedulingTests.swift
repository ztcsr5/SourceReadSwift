import SwiftUI
import WebKit
import XCTest
@testable import SourceReadSwift

@MainActor final class ReaderScrollSchedulingTests: XCTestCase {
    private func surface(chapters: Int, target: Int? = nil, onVisible: @escaping (Int) -> Void) -> WebScrollReaderView {
        let sections = (0..<chapters).map { index in
            WebReaderSection(chapterIndex: index, title: "连续第\(index)章", paragraphs: (0..<60).map { paragraph in
                "【\(index)-\(paragraph)】" + String(repeating: "窗外的风吹过树梢，正文继续向下。", count: 8)
            })
        }
        return WebScrollReaderView(sections: sections, contentFingerprint: "chapters-\(chapters)", resetToken: "scroll-book",
            fontSize: 20, lineSpacing: 8, pagePadding: 20, letterSpacing: 0, paragraphSpacing: 12,
            paragraphIndent: 40, titleSpacing: 16, footerHeight: 24, topInset: 50,
            textColor: .black, surfaceColor: .white, highlightColor: .yellow, currentParagraphIndex: -1,
            scrollTarget: target, scrollRequestKey: target.map { "jump-\($0)" }, animatedScrollDuration: 0,
            textSelectionEnabled: false, onVisibleParagraph: onVisible)
    }

    /// The product budget below is about scroll scheduling, not about how long
    /// simctl needs to spawn a WebContent process. CI 43318166559 logged
    /// "WebContent process took 30.943364 seconds to launch" and then failed
    /// every later check on the same dead process, so warm a real surface
    /// first and assert only afterwards.
    private func warmWebKitSurface() async throws {
        let warm = surface(chapters: 1) { _ in }
        let coordinator = warm.makeCoordinator()
        let web = coordinator.makeWebView(initialView: warm)
        let host = ScrollSchedulingWindow(web: web)
        defer { coordinator.tearDown(webView: web); host.close() }
        for _ in 0..<600 {
            let state = (try? await web.evaluateJavaScript("document.readyState")) as? String
            if coordinator.contentMountCount == 1, state == "complete" { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw WebKitWarmupFailure.contentProcessUnavailable
    }

    private func waitUntil(_ condition: () async throws -> Bool) async throws {
        for _ in 0..<100 {
            let fulfilled = try await condition()
            if fulfilled { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The real WebKit surface did not reach its expected state within five seconds")
    }

    func testPrefetchDuringDragAndDecelerationCoalescesWithoutLosingMountedPosition() async throws {
        try await warmWebKitSurface()
        var visible = -1
        let initial = surface(chapters: 1) { visible = $0 }
        let coordinator = initial.makeCoordinator()
        let web = coordinator.makeWebView(initialView: initial)
        let host = ScrollSchedulingWindow(web: web)
        defer { coordinator.tearDown(webView: web); host.close() }
        try await waitUntil { coordinator.contentMountCount == 1 && visible >= 0 && web.scrollView.contentSize.height > 4000 }
        _ = try await web.evaluateJavaScript("window.scrollTo(0,600);window.originalProse=document.querySelector('.para');true;")
        try await waitUntil { web.scrollView.contentOffset.y > 590 }
        let initialY = web.scrollView.contentOffset.y
        coordinator.scrollViewWillBeginDragging(web.scrollView)
        coordinator.update(view: surface(chapters: 2) { visible = $0 }, webView: web)
        coordinator.update(view: surface(chapters: 3) { visible = $0 }, webView: web)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(coordinator.contentMountCount, 1, "Downloads must not mount offscreen prose while dragging")
        coordinator.scrollViewDidEndDragging(web.scrollView, willDecelerate: true)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(coordinator.contentMountCount, 1, "Lifting the finger does not end native inertia")
        // Position reports from the mounted document must remain accepted while a newer window waits.
        visible = -1
        _ = try await web.evaluateJavaScript("window.__reader.scrollToFlat(2,false,'mounted-report',window.__reader.state.revision,0);")
        try await waitUntil { visible >= 0 }
        let documentY = try await web.evaluateJavaScript("window.scrollY") as? Double
        let readingY = try XCTUnwrap(documentY)
        // The bridge acknowledgement precedes UIKit's next remote layer commit.
        try await waitUntil { abs(web.scrollView.contentOffset.y - readingY) < 1 }
        coordinator.scrollViewDidEndDecelerating(web.scrollView)
        try await waitUntil { coordinator.contentMountCount == 2 }
        let count = try await web.evaluateJavaScript("document.querySelectorAll('.chapter').length") as? Int
        let sameProse = try await web.evaluateJavaScript("window.originalProse===document.querySelector('.para')") as? Bool
        XCTAssertEqual(count, 3)
        XCTAssertEqual(sameProse, true)
        XCTAssertEqual(web.scrollView.contentOffset.y, readingY, accuracy: 1)
        XCTAssertGreaterThan(initialY, 0)
        XCTAssertFalse(coordinator.isScrollInteractionActive)
    }

    func testNearEndStillAppendsBeforeNativeInertiaRunsOutOfProse() async throws {
        try await warmWebKitSurface()
        var visible = -1
        let initial = surface(chapters: 1) { visible = $0 }
        let coordinator = initial.makeCoordinator()
        let web = coordinator.makeWebView(initialView: initial)
        let host = ScrollSchedulingWindow(web: web)
        defer { coordinator.tearDown(webView: web); host.close() }
        try await waitUntil { coordinator.contentMountCount == 1 && visible >= 0 && web.scrollView.contentSize.height > 4000 }
        _ = try await web.evaluateJavaScript("window.scrollTo(0,document.documentElement.scrollHeight-window.innerHeight*2);")
        try await waitUntil { web.scrollView.contentSize.height - web.scrollView.contentOffset.y < web.bounds.height * 3 }
        let before = web.scrollView.contentOffset.y
        coordinator.scrollViewWillBeginDragging(web.scrollView)
        coordinator.update(view: surface(chapters: 2) { visible = $0 }, webView: web)
        try await waitUntil { coordinator.contentMountCount == 2 }
        XCTAssertTrue(coordinator.isScrollInteractionActive)
        XCTAssertEqual(web.scrollView.contentOffset.y, before, accuracy: 1)
        let count = try await web.evaluateJavaScript("document.querySelectorAll('.chapter').length") as? Int
        XCTAssertEqual(count, 2)
    }

    func testDragStartingDuringSerializationDiscardsTheSupersededWindow() async throws {
        try await warmWebKitSurface()
        var visible = -1
        let initial = surface(chapters: 1) { visible = $0 }
        let coordinator = initial.makeCoordinator()
        let web = coordinator.makeWebView(initialView: initial)
        let host = ScrollSchedulingWindow(web: web)
        defer { coordinator.tearDown(webView: web); host.close() }
        try await waitUntil { coordinator.contentMountCount == 1 && visible >= 0 && web.scrollView.contentSize.height > 4000 }
        // Start the build while idle, then synchronously begin dragging before
        // its MainActor continuation can send the resulting JSON to WebKit.
        coordinator.update(view: surface(chapters: 2) { visible = $0 }, webView: web)
        coordinator.scrollViewWillBeginDragging(web.scrollView)
        coordinator.update(view: surface(chapters: 3) { visible = $0 }, webView: web)
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(coordinator.contentMountCount, 1)
        coordinator.scrollViewDidEndDragging(web.scrollView, willDecelerate: false)
        try await waitUntil { coordinator.contentMountCount == 2 }
        let count = try await web.evaluateJavaScript("document.querySelectorAll('.chapter').length") as? Int
        XCTAssertEqual(count, 3, "The intermediate two-chapter payload must never mount")
    }

    func testExplicitChapterJumpDoesNotWaitForAnUnrelatedDrag() async throws {
        try await warmWebKitSurface()
        var visible = -1
        let initial = surface(chapters: 1) { visible = $0 }
        let coordinator = initial.makeCoordinator()
        let web = coordinator.makeWebView(initialView: initial)
        let host = ScrollSchedulingWindow(web: web)
        defer { coordinator.tearDown(webView: web); host.close() }
        try await waitUntil { coordinator.contentMountCount == 1 && visible >= 0 }
        coordinator.scrollViewWillBeginDragging(web.scrollView)
        coordinator.update(view: surface(chapters: 2, target: 61) { visible = $0 }, webView: web)
        try await waitUntil { coordinator.contentMountCount == 2 && visible == 61 }
        try await waitUntil { web.scrollView.contentOffset.y > web.bounds.height * 3 }
    }

    func testPositionReportsKeepTheirChapterWhileAChangedWindowWaitsToMount() {
        let first = WebReaderSection(chapterIndex: 0, title: "前章", paragraphs: ["一", "二"])
        let second = WebReaderSection(chapterIndex: 1, title: "当前章", paragraphs: ["三", "四", "五"])
        XCTAssertEqual(ReaderWebPositionMapper.remap(1, from: [second], to: [first, second]), 4)
        XCTAssertEqual(ReaderWebPositionMapper.remap(4, from: [first, second], to: [second]), 1)
        XCTAssertNil(ReaderWebPositionMapper.remap(1, from: [first], to: [second]), "An evicted chapter cannot overwrite another chapter's progress")
    }
}

/// Distinguishes "the simulator never gave us a WebContent process" from a
/// real scroll-scheduling regression. Without this split, a 30 s process
/// launch is reported as five product failures on one dead surface.
enum WebKitWarmupFailure: Error, CustomStringConvertible {
    case contentProcessUnavailable

    var description: String {
        "No usable WebKit content process within 30 s; scroll scheduling was not measured"
    }
}

@MainActor private final class ScrollSchedulingWindow {
    private let window: UIWindow
    private weak var previous: UIWindow?

    init(web: WKWebView) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        previous = scene?.windows.first(where: \.isKeyWindow)
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.addSubview(web)
        web.frame = CGRect(x: 0, y: 0, width: 390, height: 760)
    }

    func close() {
        window.isHidden = true
        previous?.makeKey()
    }
}
