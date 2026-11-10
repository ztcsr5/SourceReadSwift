import XCTest
@testable import SourceReadSwift

final class ReaderNavigationSessionTests: XCTestCase {
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
