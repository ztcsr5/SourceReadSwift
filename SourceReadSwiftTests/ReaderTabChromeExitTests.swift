import SwiftUI
import XCTest
import UIKit
@testable import SourceReadSwift

final class ReaderTabChromeExitTests: XCTestCase {
    @MainActor func testRealUIKitPopReleasesOwnershipBeforeTheSourceDisappears() async throws {
        let app = AppState(), owner = UUID()
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
        for _ in 0..<20 {
            if host.view.window != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertNotNil(host.view.window)
        app.acquireTabChromeHidden(owner: owner)
        navigation.popViewController(animated: true)
        XCTAssertFalse(app.isTabChromeHidden, "A real pop must release before its completion callback")
        XCTAssertFalse(source.hasDisappeared, "This assertion must run before onDisappear, not after waiting for it")
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
    private(set) var hasDisappeared = false
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        hasDisappeared = true
    }
}
