import XCTest
import UIKit
import WebKit
@testable import SourceReadSwift

@MainActor
final class ReaderCompatibilityNavigationTests: XCTestCase {
    func testUIKitCompatibilityCancellationRetainsThePageThenCommitsOneReturn() async throws {
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
        let web = WKWebView(frame: window.bounds)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        reader.view.addSubview(web)
        web.loadHTMLString("<meta name='viewport' content='width=device-width'><p style='height:4000px'>保留正文</p>", baseURL: nil)
        navigation.pushViewController(reader, animated: false)
        var documentReady = false
        for _ in 0..<200 {
            documentReady = (try? await web.evaluateJavaScript("document.readyState === 'complete'")) as? Bool == true
            if documentReady { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertTrue(documentReady)
        _ = try await web.evaluateJavaScript("window.scrollTo(0, 700)")
        let originalValue = try await web.evaluateJavaScript("window.scrollY")
        let originalOffset = try XCTUnwrap(originalValue as? Double)
        XCTAssertGreaterThan(originalOffset, 600)

        let session = ReaderNavigationSession()
        session.didAppear()
        var cleanups = 0
        session.registerExit(owner: UUID()) { cleanups += 1 }
        let transition = ReaderCompatibilityTransition(session: session, source: { cover })
        let delegate = CompatibilityNavigationDelegate(transition: transition, reader: reader)
        navigation.delegate = delegate
        transition.attach(to: navigation.view) { navigation.popViewController(animated: true) }
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
