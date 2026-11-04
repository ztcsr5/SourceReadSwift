import SwiftUI
import XCTest
@testable import SourceReadSwift

final class ForestReadingCardTests: XCTestCase {
    @MainActor func testMountedForestCardKeepsLongTitlesWithinTheCompactEnvelope() throws {
        var book = BookshelfBook(id: "forest-mounted", title: "沿着很长很长的林间小路走到纸张的尽头再回到这里",
            author: "一位名字也很长的作者", coverURL: nil, sourceName: "本地", sourceURL: "local://text",
            bookURL: "local://forest-mounted", intro: nil)
        book.lastReadAt = Date()
        book.currentChapterTitle = "第六十四章 写给下一页的一封很长的信"
        book.totalChapters = 120
        let host = UIHostingController(rootView: ForestReadingCard(book: book, heroNamespace: nil)
            .environment(\.dynamicTypeSize, .large))
        for width: CGFloat in [288, 358] {
            let size = host.sizeThatFits(in: CGSize(width: width, height: 600))
            XCTAssertEqual(size.width, width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(size.height, 185)
            XCTAssertLessThanOrEqual(size.height, 205)
        }
        let accessible = UIHostingController(rootView: ForestReadingCard(book: book, heroNamespace: nil)
            .environment(\.dynamicTypeSize, .accessibility3))
        XCTAssertGreaterThan(accessible.sizeThatFits(in: CGSize(width: 288, height: 1000)).height, 205)
    }
}
