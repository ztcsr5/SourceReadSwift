import XCTest
@testable import SourceReadSwift

final class B18PlusServiceTests: XCTestCase {

    func testB18PlusBlocking() {
        let service = B18PlusService.shared

        // Verify blocked host
        XCTAssertTrue(service.isRestricted(url: "https://8cyu.com/book/123"))
        XCTAssertTrue(service.isRestricted(url: "http://www.8cyu.com/"))
        XCTAssertTrue(service.isRestricted(url: "https://sg00.xyz/novel/456"))

        // Verify blocked keyword in title
        XCTAssertTrue(service.isRestricted(url: "https://normal-domain.com", name: "某种8cyu.com的小说"))

        // Verify normal domains are not blocked
        XCTAssertFalse(service.isRestricted(url: "https://www.biquge8.xyz/book/1"))
        XCTAssertFalse(service.isRestricted(url: "https://gutenberg.org/ebooks/1", name: "Pride and Prejudice"))
    }
}
