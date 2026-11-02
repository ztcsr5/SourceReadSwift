import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ReaderTabChromeExitTests: XCTestCase {
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
