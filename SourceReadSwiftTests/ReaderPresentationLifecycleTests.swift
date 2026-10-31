import XCTest
@testable import SourceReadSwift

final class ReaderPresentationLifecycleTests: XCTestCase {
    func testTocCoverDoesNotEndSessionOrReplayInitialPosition() {
        var lifecycle = ReaderPresentationLifecycle()
        XCTAssertTrue(lifecycle.beginAppearance())
        for _ in 0..<3 {
            XCTAssertFalse(lifecycle.endAppearance(chapterListPresented: true), "TOC presentation must not cancel the reader's pending jump")
            XCTAssertFalse(lifecycle.beginAppearance(), "TOC dismissal must not restore the initial chapter or encode the shelf again")
        }
    }

    func testRealReaderExitStillCleansUpAndReappearanceInitializes() {
        var lifecycle = ReaderPresentationLifecycle()
        XCTAssertTrue(lifecycle.beginAppearance())
        XCTAssertTrue(lifecycle.endAppearance(chapterListPresented: false))
        XCTAssertTrue(lifecycle.beginAppearance())
        XCTAssertFalse(lifecycle.endAppearance(chapterListPresented: true))
        XCTAssertFalse(lifecycle.beginAppearance())
        XCTAssertTrue(lifecycle.endAppearance(chapterListPresented: false))
    }
}
