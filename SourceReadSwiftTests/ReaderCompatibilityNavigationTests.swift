import XCTest
import UIKit
import WebKit
@testable import SourceReadSwift

@MainActor
final class ReaderCompatibilityNavigationTests: XCTestCase {
    func testUIKitCompatibilityCancellationRetainsThePageThenCommitsOneReturn() async throws {
        try await verifyCompatibilityReturn(reducesMotion: false)
    }

    func testReducedMotionKeepsCompatibilityReturnInteractiveWithoutZoomingCover() async throws {
        try await verifyCompatibilityReturn(reducesMotion: true)
    }

    private func verifyCompatibilityReturn(reducesMotion: Bool) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        let root = UIViewController()
        let cover = UIView(frame: CGRect(x: 24, y: 120, width: 96, height: 144))
        cover.backgroundColor = .brown
        root.view.addSubview(cover)
        let navigation = UINavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        let reader = UIViewController()
        reader.view.backgroundColor = .white
        let presented = expectation(description: "The production WebView is positioned before testing navigation")
        let surface = WebScrollReaderView(
            sections: [WebReaderSection(chapterIndex: 0, title: "兼容返回",
                paragraphs: (0..<60).map { "第\($0)段。取消后保留正在阅读的真实正文位置。" })],
            contentFingerprint: "compatibility-position", fontSize: 20, lineSpacing: 8,
            pagePadding: 20, letterSpacing: 0, paragraphSpacing: 12, paragraphIndent: 40,
            titleSpacing: 16, footerHeight: 12, topInset: 50, textColor: .black,
            highlightColor: .yellow, currentParagraphIndex: -1, scrollTarget: 30,
            scrollRequestKey: "compatibility-paragraph-30", animatedScrollDuration: 0,
            textSelectionEnabled: false, onVisibleParagraph: { _ in }, onPresented: { presented.fulfill() })
        let coordinator = surface.makeCoordinator()
        let web = coordinator.makeWebView(initialView: surface)
        web.frame = window.bounds
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        reader.view.addSubview(web)
        navigation.pushViewController(reader, animated: false)
        defer { coordinator.tearDown(webView: web) }
        await fulfillment(of: [presented], timeout: 10)
        let originalValue = try await web.evaluateJavaScript("window.scrollY")
        let originalOffset = try XCTUnwrap(originalValue as? Double)
        XCTAssertGreaterThan(originalOffset, 600)

        let session = ReaderNavigationSession()
        session.didAppear()
        var cleanups = 0
        session.registerExit(owner: UUID()) { cleanups += 1 }
        var coverLookups = 0
        let transition = ReaderCompatibilityTransition(session: session, source: {
            coverLookups += 1
            return cover
        }, reducesMotion: { reducesMotion })
        XCTAssertEqual(transition.shouldAnimateReturn, !reducesMotion,
                       "A button return should not force animation when Reduce Motion is enabled")
        let delegate = CompatibilityNavigationDelegate(transition: transition, reader: reader)
        navigation.delegate = delegate
        transition.attach(to: navigation.view) { [weak transition] in
            guard let transition else { return }
            XCTAssertTrue(transition.shouldAnimateReturn, "An edge return needs the cancellable UIKit transaction")
            navigation.popViewController(animated: transition.shouldAnimateReturn)
        }
        defer { transition.detach() }

        for cycle in 1...3 {
            session.willLeave()
            transition.updateGesture(state: .began, translation: .zero, velocity: .zero, width: window.bounds.width)
            transition.updateGesture(state: .changed, translation: CGPoint(x: 48, y: 0), velocity: .zero,
                                     width: window.bounds.width)
            transition.updateGesture(state: .ended, translation: CGPoint(x: 48, y: 0), velocity: .zero,
                                     width: window.bounds.width)
            let settled = await eventually { delegate.arrivals == cycle }
            XCTAssertTrue(settled)
            XCTAssertTrue(navigation.topViewController === reader)
            XCTAssertTrue(web.superview === reader.view)
            XCTAssertTrue(reader.view.transform.isIdentity)
            XCTAssertEqual(reader.view.alpha, 1)
            XCTAssertEqual(cover.alpha, 1)
            XCTAssertEqual(session.phase, .reading)
            XCTAssertEqual(cleanups, 0)
            let offsetValue = try await web.evaluateJavaScript("window.scrollY")
            let offset = try XCTUnwrap(offsetValue as? Double)
            XCTAssertEqual(offset, originalOffset, accuracy: 1)
        }

        session.willLeave()
        transition.updateGesture(state: .began, translation: .zero, velocity: .zero, width: window.bounds.width)
        transition.updateGesture(state: .changed, translation: CGPoint(x: 300, y: 0), velocity: .zero,
                                 width: window.bounds.width)
        transition.updateGesture(state: .ended, translation: CGPoint(x: 300, y: 0), velocity: .zero,
                                 width: window.bounds.width)
        let returned = await eventually { delegate.arrivals == 4 }
        XCTAssertTrue(returned)
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertEqual(session.phase, .closed)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(cover.alpha, 1)
        if reducesMotion {
            XCTAssertEqual(coverLookups, 0, "Reduced-motion returns must not fetch or scale the cover")
        } else {
            XCTAssertGreaterThan(coverLookups, 0, "The normal transition must resolve the live cover")
        }
    }

    private func eventually(_ predicate: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        return predicate()
    }
}

@MainActor
private final class CompatibilityNavigationDelegate: NSObject, UINavigationControllerDelegate {
    let transition: ReaderCompatibilityTransition
    let reader: UIViewController
    var arrivals = 0

    init(transition: ReaderCompatibilityTransition, reader: UIViewController) {
        self.transition = transition
        self.reader = reader
    }

    func navigationController(_ navigationController: UINavigationController,
                              animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        transition.animator(isOpening: operation == .push)
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: UIViewControllerAnimatedTransitioning) -> UIViewControllerInteractiveTransitioning? {
        transition.interaction
    }

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController,
                              animated: Bool) {
        arrivals += 1
        if viewController === reader { transition.session.didAppear() }
        else { transition.session.commitExit() }
        transition.didSettle()
    }
}
