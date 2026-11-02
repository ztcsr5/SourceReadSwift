import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class Release117PolishTests: XCTestCase {
    @MainActor func testReadingCardHasCompactRegularHeightAndUnclippedAccessibleLayout() {
        let book = BookshelfBook(id: "polish", title: "写给远方的一封信", author: "纸间",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://polish", intro: nil)
        for width: CGFloat in [288, 358, 398] {
            let regular = UIHostingController(rootView: ReadingHeroCard(book: book).environment(\.dynamicTypeSize, .large))
                .sizeThatFits(in: CGSize(width: width, height: 3000))
            let accessible = UIHostingController(rootView: ReadingHeroCard(book: book).environment(\.dynamicTypeSize, .accessibility3))
                .sizeThatFits(in: CGSize(width: width, height: 3000))
            XCTAssertGreaterThanOrEqual(regular.height, 160)
            XCTAssertLessThanOrEqual(regular.height, 280, "One current book must not consume most of the home screen")
            XCTAssertEqual(regular.width, width, accuracy: 1)
            XCTAssertGreaterThan(accessible.height, regular.height)
        }
    }
}
