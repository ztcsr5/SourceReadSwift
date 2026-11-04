import SwiftUI
import XCTest
import UIKit
import Combine
@testable import SourceReadSwift

final class ReaderTabChromeExitTests: XCTestCase {
    @MainActor func testInteractivePopIsRecognizedBeforeTheSourceLeavesTheStack() {
        let root = UIViewController(), reader = UIViewController(), pushed = UIViewController()
        let navigation = UINavigationController(rootViewController: root)
        navigation.pushViewController(reader, animated: false)
        XCTAssertTrue(ReaderNativePopPolicy.isPop(from: reader, to: root, in: navigation, isInteractive: true))
        XCTAssertFalse(ReaderNativePopPolicy.isPop(from: reader, to: pushed, in: navigation, isInteractive: true))
        XCTAssertFalse(ReaderNativePopPolicy.isPop(from: reader, to: pushed, in: navigation, isInteractive: false))
    }

    @MainActor func testRealUIKitPopReleasesOwnershipBeforeTheSourceDisappears() async throws {
        let app = AppState(), owner = UUID()
        let animationsWereEnabled = UIView.areAnimationsEnabled
        UIView.setAnimationsEnabled(true)
        defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let source = ReaderExitTimingHost()
        let host = UIHostingController(rootView: Color.clear
            .background(ReaderTabChromeExitBridge(owner: owner)).environmentObject(app))
        source.addChild(host); source.view.addSubview(host.view)
        host.view.frame = window.bounds; host.didMove(toParent: source)
        navigation.pushViewController(source, animated: false)
        for _ in 0..<50 {
            if source.hasAppeared && host.view.window != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(source.hasAppeared)
        XCTAssertNotNil(host.view.window)
        app.acquireTabChromeHidden(owner: owner)
        let released = expectation(description: "The real pop releases its reader owner")
        var releasedBeforeDisappearance = false
        let observation = app.$isTabChromeHidden.dropFirst().filter { !$0 }.prefix(1).sink { _ in
            releasedBeforeDisappearance = !source.hasDisappeared
            XCTAssertFalse(source.hasDisappeared, "The release must precede onDisappear, not merely follow the completed pop")
            released.fulfill()
        }
        defer { observation.cancel() }
        navigation.popViewController(animated: true)
        // UIKit can start the transition on the next run-loop turn. Observe the
        // actual ownership event, while still requiring it before disappearance.
        await fulfillment(of: [released], timeout: 2.5)
        XCTAssertFalse(app.isTabChromeHidden, "A real pop must release before its completion callback")
        XCTAssertTrue(releasedBeforeDisappearance)
        for _ in 0..<50 {
            if source.hasDisappeared { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(source.hasDisappeared)
    }

    @MainActor func testBothReaderOwnersReleaseBeforeCompletionAndReacquireOnCancelledPop() {
        let app = AppState(), gateway = UUID(), reader = UUID()
        let gatewayExit = ReaderTabChromeExitController(), readerExit = ReaderTabChromeExitController()
        gatewayExit.configure(onLeaving: { app.releaseTabChromeHidden(owner: gateway) },
            onCancelled: { app.acquireTabChromeHidden(owner: gateway) })
        readerExit.configure(onLeaving: { app.releaseTabChromeHidden(owner: reader) },
            onCancelled: { app.acquireTabChromeHidden(owner: reader) })
        app.acquireTabChromeHidden(owner: gateway); app.acquireTabChromeHidden(owner: reader)
        gatewayExit.prepareForExit()
        XCTAssertTrue(app.isTabChromeHidden, "One remaining reader owner must still hide the tabs")
        readerExit.prepareForExit()
        XCTAssertFalse(app.isTabChromeHidden, "Tabs must be ready before waiting for pop completion/onDisappear")
        gatewayExit.finishExit(cancelled: true); readerExit.finishExit(cancelled: true)
        XCTAssertTrue(app.isTabChromeHidden, "Cancelled return must keep the still-visible reader immersive")
        gatewayExit.prepareForExit(); readerExit.prepareForExit()
        gatewayExit.finishExit(cancelled: false); readerExit.finishExit(cancelled: false)
        XCTAssertFalse(app.isTabChromeHidden)
    }

    @MainActor func testRepeatedCallbacksDoNotReleaseUnrelatedOwnersOrRestoreACompletedExit() {
        let app = AppState(), unrelated = UUID(), reader = UUID()
        let controller = ReaderTabChromeExitController()
        var releases = 0, restores = 0
        controller.configure(onLeaving: { releases += 1; app.releaseTabChromeHidden(owner: reader) },
            onCancelled: { restores += 1; app.acquireTabChromeHidden(owner: reader) })
        app.acquireTabChromeHidden(owner: unrelated); app.acquireTabChromeHidden(owner: reader)
        controller.prepareForExit(); controller.prepareForExit()
        XCTAssertEqual(releases, 1)
        XCTAssertTrue(app.isTabChromeHidden)
        controller.finishExit(cancelled: false); controller.finishExit(cancelled: true)
        XCTAssertEqual(restores, 0)
        app.releaseTabChromeHidden(owner: unrelated)
        XCTAssertFalse(app.isTabChromeHidden)
    }
}

private final class ReaderExitTimingHost: UIViewController {
    private(set) var hasAppeared = false
    private(set) var hasDisappeared = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        hasDisappeared = true
    }
}
