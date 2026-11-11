import XCTest
import SwiftUI
@testable import SourceReadSwift

final class ReaderNavigationSessionTests: XCTestCase {
    @MainActor func testZoomBeginEvidenceExcludesPreflightAndRejectedStarts() {
        let session = ReaderNavigationSession()
        session.recordZoomDecision(location: .zero, willBegin: false, accepted: true)
        session.recordZoomDecision(location: .zero, willBegin: true, accepted: false)
        XCTAssertEqual(session.zoomDecisionCount, 2)
        XCTAssertEqual(session.zoomBeginCount, 0)
        session.recordZoomDecision(location: .zero, willBegin: true, accepted: true)
        XCTAssertEqual(session.zoomDecisionCount, 3)
        XCTAssertEqual(session.zoomBeginCount, 1)
    }

    func testHostingEnvironmentSnapshotsOnlyActualPresentationChanges() {
        var values = EnvironmentValues()
        values.colorScheme = .light
        let initial = ReaderHostingEnvironment(values: values)
        XCTAssertEqual(initial, ReaderHostingEnvironment(values: values))
        values.colorScheme = .dark
        XCTAssertNotEqual(initial, ReaderHostingEnvironment(values: values))
        values.colorScheme = .light
        XCTAssertEqual(initial, ReaderHostingEnvironment(values: values), "The snapshot cannot retain a live foreign environment graph")
    }
    @MainActor func testActualRenderedContentOpensTheGateWithoutPreferencePropagationOrATimer() {
        let session = ReaderNavigationSession()
        XCTAssertFalse(session.isContentReady)
        session.recordPresentedContent()
        XCTAssertTrue(session.hasPresentedContent)
        XCTAssertTrue(session.isContentReady)
        XCTAssertTrue(session.didReceiveReady)
        session.willLeave()
        session.didAppear()
        XCTAssertTrue(session.isContentReady)
    }

    @MainActor func testActionableLoadErrorCanRevealWithoutClaimingRenderedProse() {
        let session = ReaderNavigationSession()
        session.recordReadyReceipt()
        XCTAssertTrue(session.isContentReady)
        XCTAssertFalse(session.hasPresentedContent)
        session.commitExit()
        XCTAssertEqual(session.phase, .closed)
    }
    @MainActor func testChapterSelectionUsesTheExistingSessionAndStopsAfterCommittedExit() {
        let session = ReaderNavigationSession(bookID: "book")
        var selections: [Int] = []
        session.registerChapterSelection { selections.append($0) }
        session.didAppear()
        XCTAssertTrue(session.selectChapter(3))
        session.willLeave()
        session.didAppear()
        XCTAssertTrue(session.selectChapter(4))
        session.commitExit()
        XCTAssertFalse(session.selectChapter(5))
        XCTAssertEqual(selections, [3, 4])
    }
    @MainActor func testCancelledReturnKeepsTheSessionAndDoesNotRunCleanup() {
        let session = ReaderNavigationSession()
        let identity = session.id
        var cleanups = 0
        session.registerExit(owner: UUID()) { cleanups += 1 }
        session.didAppear()
        for _ in 0..<20 {
            session.willLeave()
            session.didAppear()
            XCTAssertEqual(session.id, identity)
            XCTAssertEqual(session.phase, .reading)
            XCTAssertEqual(cleanups, 0)
        }
    }

    @MainActor func testCommittedExitRunsEveryOwnerOnceAndCannotBeCancelledAfterwards() {
        let session = ReaderNavigationSession()
        let owner = UUID()
        var oldCleanup = 0, currentCleanup = 0, anotherCleanup = 0
        session.registerExit(owner: owner) { oldCleanup += 1 }
        session.registerExit(owner: owner) { currentCleanup += 1 }
        session.registerExit(owner: UUID()) { anotherCleanup += 1 }
        session.didAppear()
        session.willLeave()
        session.commitExit()
        session.commitExit()
        session.didAppear()
        XCTAssertEqual(session.phase, .closed)
        XCTAssertEqual(oldCleanup, 0)
        XCTAssertEqual(currentCleanup, 1)
        XCTAssertEqual(anotherCleanup, 1)
    }

    @MainActor func testARepeatedRequestHasANewPresentationIdentity() {
        XCTAssertNotEqual(ReaderNavigationSession().id, ReaderNavigationSession().id)
    }
}
