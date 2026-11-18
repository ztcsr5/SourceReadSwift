import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderPageTurnRequestTests: XCTestCase {
    func testMismatchedDeliveryDoesNotConsumeRequest() {
        let request = ReaderPageTurnRequest(direction: 1, pageIdentity: "page-7", style: .curl)

        XCTAssertFalse(request.claim(pageIdentity: "page-8", style: .curl))
        XCTAssertFalse(request.claim(pageIdentity: "page-7", style: .slide))
        XCTAssertTrue(request.claim(pageIdentity: "page-7", style: .curl))
        XCTAssertFalse(request.claim(pageIdentity: "page-7", style: .curl))
    }

    func testDiscardedRequestCannotReplayAfterItsPageReturns() {
        let request = ReaderPageTurnRequest(direction: 1, pageIdentity: "page-7", style: .curl)

        XCTAssertFalse(request.claim(pageIdentity: "page-8", style: .curl))
        request.discard()

        XCTAssertFalse(request.claim(pageIdentity: "page-7", style: .curl))
    }

    func testMatchingRequestIsClaimedExactlyOnce() {
        let request = ReaderPageTurnRequest(direction: -1, pageIdentity: "page-7", style: .curl)

        XCTAssertTrue(request.claim(pageIdentity: "page-7", style: .curl))
        XCTAssertFalse(request.claim(pageIdentity: "page-7", style: .curl))
    }

}
