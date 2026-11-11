import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import SourceReadSwift

final class ReaderExitSwipeTests: XCTestCase {
    func testExitRequiresMenuAndNoSettingsOrCover() {
        XCTAssertTrue(ReaderExitSwipePolicy.isEnabled(menuVisible: true, settingsVisible: false, coverPresented: false))
        XCTAssertFalse(ReaderExitSwipePolicy.isEnabled(menuVisible: false, settingsVisible: false, coverPresented: false))
        XCTAssertFalse(ReaderExitSwipePolicy.isEnabled(menuVisible: true, settingsVisible: true, coverPresented: false))
        XCTAssertFalse(ReaderExitSwipePolicy.isEnabled(menuVisible: true, settingsVisible: false, coverPresented: true))
    }

    func testNativeReturnAllowsProseAndPagedButProtectsSelectionAndSettings() {
        XCTAssertTrue(ReaderSystemReturnPolicy.isEnabled(isScroll: true, menuVisible: false, blocked: false, selectionEnabled: false))
        XCTAssertTrue(ReaderSystemReturnPolicy.isEnabled(isScroll: false, menuVisible: false, blocked: false, selectionEnabled: false))
        XCTAssertTrue(ReaderSystemReturnPolicy.isEnabled(isScroll: false, menuVisible: true, blocked: false, selectionEnabled: false))
        XCTAssertFalse(ReaderSystemReturnPolicy.isEnabled(isScroll: true, menuVisible: false, blocked: false, selectionEnabled: true))
        XCTAssertFalse(ReaderSystemReturnPolicy.isEnabled(isScroll: true, menuVisible: true, blocked: true, selectionEnabled: false))
    }

    func testProseFallbackDoesNotCompeteWithTheOrdinaryNativeZoomReturn() {
        XCTAssertTrue(ReaderExitSwipePolicy.isProseFallbackEnabled(reducesMotion: true, allowsBookReturn: true))
        XCTAssertFalse(ReaderExitSwipePolicy.isProseFallbackEnabled(reducesMotion: false, allowsBookReturn: true))
        XCTAssertFalse(ReaderExitSwipePolicy.isProseFallbackEnabled(reducesMotion: true, allowsBookReturn: false))
    }

    func testOnlyAnActiveOrCompletedNativeReturnSuppressesFallback() {
        for state in [UIGestureRecognizer.State.began, .changed, .ended] {
            XCTAssertTrue(ReaderExitSwipePolicy.isSystemReturnActive(state))
        }
        for state in [UIGestureRecognizer.State.possible, .failed, .cancelled] {
            XCTAssertFalse(ReaderExitSwipePolicy.isSystemReturnActive(state))
        }
    }

    func testDeliberateRightwardSwipePassesDistanceThreshold() {
        XCTAssertTrue(finish(x: 90))
        XCTAssertFalse(finish(x: 40))
        XCTAssertTrue(finish(x: 140, width: 1024))
        XCTAssertFalse(finish(x: 100, width: 1024))
    }

    func testFastFlickStillNeedsMinimumTravelAndRightwardVelocity() {
        XCTAssertTrue(finish(x: 40, velocity: CGPoint(x: 800, y: 30)))
        XCTAssertFalse(finish(x: 20, velocity: CGPoint(x: 1200, y: 0)))
        XCTAssertFalse(finish(x: 40, velocity: CGPoint(x: -800, y: 0)))
        XCTAssertFalse(finish(x: 40, velocity: CGPoint(x: 800, y: 900)))
    }

    func testLeftwardVerticalAndDiagonalGesturesDoNotExit() {
        for point in [CGPoint(x: -100, y: 0), CGPoint(x: 0, y: 200), CGPoint(x: 100, y: 100)] {
            XCTAssertFalse(ReaderExitSwipePolicy.shouldFinish(translation: point, velocity: .zero, width: 390))
        }
    }

    func testInvalidGeometryAndMovementDoNotExit() {
        for width: CGFloat in [0, -100, .nan, .infinity] {
            XCTAssertFalse(finish(x: 200, width: width))
        }
        XCTAssertFalse(finish(x: .nan))
        XCTAssertFalse(finish(x: .infinity))
    }

    @MainActor func testRecognizerUsesLeftEdgeAndAttachesOnlyToReaderParent() {
        let (parent, controller) = mountedController()
        XCTAssertEqual(controller.edgePan.edges, .left)
        XCTAssertTrue(controller.edgePan.view === parent.view)
        XCTAssertEqual(parent.view.gestureRecognizers?.filter { $0 === controller.edgePan }.count, 1)
        controller.configure(enabled: true, onExit: {})
        XCTAssertEqual(parent.view.gestureRecognizers?.filter { $0 === controller.edgePan }.count, 1)
        controller.detach()
        XCTAssertNil(controller.edgePan.view)
    }

    @MainActor func testMenuClosedDisablesRecognizerAndFailurePriority() {
        let (parent, controller) = mountedController()
        let child = UIView(frame: parent.view.bounds)
        parent.view.addSubview(child)
        let pagePan = UIPanGestureRecognizer()
        child.addGestureRecognizer(pagePan)
        XCTAssertFalse(controller.gestureRecognizer(controller.edgePan, shouldBeRequiredToFailBy: pagePan),
                       "The preserved legacy bridge no longer installs a global failure requirement")
        controller.configure(enabled: false, onExit: {})
        XCTAssertFalse(controller.edgePan.isEnabled)
        XCTAssertFalse(controller.gestureRecognizer(controller.edgePan, shouldBeRequiredToFailBy: pagePan))
    }

    @MainActor func testPriorityDoesNotAffectUnrelatedViewTrees() {
        let (parent, controller) = mountedController()
        defer { _ = parent }
        let unrelated = UIView(), unrelatedPan = UIPanGestureRecognizer()
        unrelated.addGestureRecognizer(unrelatedPan)
        XCTAssertFalse(controller.gestureRecognizer(controller.edgePan, shouldBeRequiredToFailBy: unrelatedPan))
        XCTAssertFalse(controller.gestureRecognizer(controller.edgePan, shouldBeRequiredToFailBy: controller.edgePan))
    }

    @MainActor func testEnabledSystemReturnDoesNotDisableFallbackOrReplaceItsDelegate() {
        if #available(iOS 18.0, *) {
            let root = UIViewController(), source = UIViewController()
            let navigation = UINavigationController(rootViewController: root)
            navigation.loadViewIfNeeded()
            navigation.pushViewController(source, animated: false)
            let bridge = ReaderExitSwipeController()
            source.addChild(bridge); source.view.addSubview(bridge.view); bridge.didMove(toParent: source)
            navigation.interactivePopGestureRecognizer?.isEnabled = true
            let nativeDelegate = navigation.interactivePopGestureRecognizer?.delegate
            navigation.setNavigationBarHidden(true, animated: false)
            bridge.configure(enabled: true, prefersSystemReturn: true, onExit: {})
            XCTAssertTrue(bridge.edgePan.isEnabled, "An enabled flag alone cannot prove that the hidden-bar native return will begin")
            XCTAssertTrue(bridge.prioritizedNavigationEdge === navigation.interactivePopGestureRecognizer)
            XCTAssertTrue(navigation.interactivePopGestureRecognizer?.delegate === nativeDelegate)
            XCTAssertTrue(navigation.interactivePopGestureRecognizer?.isEnabled == true)
            bridge.configure(enabled: true, prefersSystemReturn: false, onExit: {})
            XCTAssertTrue(bridge.edgePan.isEnabled, "Non-book and legacy entry paths keep the existing fallback")
        }
    }

    @MainActor func testProsePrioritizesOnlyTheMountedNavigationEdgeRecognizer() throws {
        guard #available(iOS 18.0, *) else { return }
        let destination = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(destination, animated: false)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }

        let edgeReturn = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
        let web = ReaderEdgeReturnWebView(frame: destination.view.bounds, configuration: WKWebViewConfiguration())
        let scrollDelegate = web.scrollView.panGestureRecognizer.delegate
        let edgeDelegate = edgeReturn.delegate
        XCTAssertNil(web.prioritizedEdgeReturn)
        destination.view.addSubview(web)
        window.layoutIfNeeded()
        web.layoutIfNeeded()
        XCTAssertTrue(web.prioritizedEdgeReturn === edgeReturn, "The mounted and laid-out prose view must install edge priority")
        XCTAssertTrue(edgeReturn.delegate === edgeDelegate)
        XCTAssertTrue(web.scrollView.panGestureRecognizer.delegate === scrollDelegate)
    }

    @MainActor func testProseEdgePriorityInstallsWhenItsParentIsMountedLater() throws {
        guard #available(iOS 18.0, *) else { return }
        let destination = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(destination, animated: false)
        let web = ReaderEdgeReturnWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 640), configuration: WKWebViewConfiguration())
        destination.view.addSubview(web)
        XCTAssertNil(web.prioritizedEdgeReturn)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        window.layoutIfNeeded()
        web.layoutIfNeeded()
        let edgeReturn = try XCTUnwrap(navigation.interactivePopGestureRecognizer)
        XCTAssertTrue(web.prioritizedEdgeReturn === edgeReturn)
    }

    @MainActor func testSuccessfulSwipeDismissesExactlyOnce() {
        let (parent, controller) = mountedController()
        defer { _ = parent }
        var exits = 0
        controller.configure(enabled: true) { exits += 1 }
        for _ in 0..<2 {
            controller.completeSwipe(translation: CGPoint(x: 120, y: 5), velocity: .zero, cancelled: false)
        }
        XCTAssertEqual(exits, 1)
        #if DEBUG
        XCTAssertEqual(controller.fallbackMotionCount, 0, "Requesting exit directly is not evidence of a recognized touch")
        #endif
    }

    @MainActor func testCancelledShortAndDisabledSwipesDoNotDismiss() {
        let (parent, controller) = mountedController()
        defer { _ = parent }
        var exits = 0
        controller.configure(enabled: true) { exits += 1 }
        controller.completeSwipe(translation: CGPoint(x: 120, y: 0), velocity: .zero, cancelled: true)
        controller.completeSwipe(translation: CGPoint(x: 10, y: 0), velocity: .zero, cancelled: false)
        controller.configure(enabled: false) { exits += 1 }
        controller.completeSwipe(translation: CGPoint(x: 120, y: 0), velocity: .zero, cancelled: false)
        XCTAssertEqual(exits, 0)
    }

    @MainActor func testSwiftUIBackgroundInstallsReaderScopedRecognizer() async throws {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        let host = UIHostingController(rootView: Color.white.ignoresSafeArea().background(
            ReaderExitSwipeBridge(enabled: true, onExit: {})
        ))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        for _ in 0..<100 {
            if let bridge = findBridge(in: host), bridge.edgePan.view != nil, bridge.view.bounds.width > 0 { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let bridge = try XCTUnwrap(findBridge(in: host))
        XCTAssertTrue(bridge.edgePan.isEnabled)
        XCTAssertNotNil(bridge.edgePan.view)
        XCTAssertFalse(bridge.edgePan.view === window)
        XCTAssertGreaterThan(bridge.view.bounds.width, 0)
        XCTAssertTrue(bridge.edgePan.view === bridge.parent?.view)
    }

    func testAutoScrollAcceptsSlowerSavedDelaysWithoutChangingOldValues() {
        for value in [11.0, 20.0, 30.0, 45.0, 60.0] {
            XCTAssertEqual(ReaderAutomationPolicy.clampedDelay(value), value)
        }
        XCTAssertEqual(ReaderAutomationPolicy.clampedDelay(120), 60)
        XCTAssertEqual(ReaderAutomationPolicy.maxDelay, 60)
    }

    private func finish(x: CGFloat, velocity: CGPoint = .zero, width: CGFloat = 390) -> Bool {
        ReaderExitSwipePolicy.shouldFinish(translation: CGPoint(x: x, y: 0), velocity: velocity, width: width)
    }

    @MainActor private func mountedController() -> (UIViewController, ReaderExitSwipeController) {
        let parent = UIViewController(), child = ReaderExitSwipeController()
        parent.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        parent.addChild(child)
        child.view.frame = parent.view.bounds
        parent.view.addSubview(child.view)
        child.didMove(toParent: parent)
        child.configure(enabled: true, onExit: {})
        return (parent, child)
    }

    @MainActor private func findBridge(in controller: UIViewController) -> ReaderExitSwipeController? {
        if let bridge = controller as? ReaderExitSwipeController { return bridge }
        for child in controller.children {
            if let bridge = findBridge(in: child) { return bridge }
        }
        return nil
    }
}
