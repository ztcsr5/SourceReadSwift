import XCTest
@testable import SourceReadSwift

final class ShelfProjectionTests: XCTestCase {
    private func book(
        id: String,
        title: String,
        author: String = "作者",
        group: String? = nil,
        sourceURL: String = "https://source.invalid",
        mediaKind: BookSourceKind? = nil,
        isPinned: Bool = false,
        addedAt: Date = Date(timeIntervalSince1970: 0),
        lastReadAt: Date? = nil,
        progress: Double = 0
    ) -> BookshelfBook {
        BookshelfBook(
            id: id, title: title, author: author, coverURL: nil,
            sourceName: "测试源", sourceURL: sourceURL, bookURL: sourceURL + "/" + id,
            intro: nil,
            totalChapters: 100,
            currentChapterIndex: Int(progress * 100),
            lastReadAt: lastReadAt,
            groupName: group,
            isPinned: isPinned,
            addedAt: addedAt,
            mediaKind: mediaKind
        )
    }

    func testGroupMediaAndQueryFiltersStayComposable() {
        let books = [
            book(id: "novel", title: "长夜", author: "甲", group: "严肃"),
            book(id: "comic", title: "长夜漫画", author: "乙", group: "严肃", mediaKind: .comic),
            book(id: "audio", title: "长夜有声", author: "丙", group: "轻松", mediaKind: .audio),
            book(id: "other", title: "白昼", author: "丁", group: "严肃")
        ]
        let result = ShelfProjection.books(
            books, group: "严肃", media: nil, query: "长夜", sort: .title,
            returnOrder: [], mediaKind: { $0.mediaKind }
        )
        XCTAssertEqual(result.map(\.id), ["novel", "comic"])
    }

    func testReturnOrderWinsOverSortAndKeepsStableSlots() {
        let books = [
            book(id: "a", title: "A"),
            book(id: "b", title: "B"),
            book(id: "c", title: "C")
        ]
        let result = ShelfProjection.books(
            books, group: nil, media: nil, query: "", sort: .title,
            returnOrder: ["c", "a", "b"], mediaKind: { $0.mediaKind }
        )
        XCTAssertEqual(result.map(\.id), ["c", "a", "b"])
    }

    func testMediaKindFallsBackToSourceAndLocalComic() {
        let books = [
            book(id: "source", title: "源漫画", sourceURL: "https://comic.invalid"),
            book(id: "local", title: "本地漫画", sourceURL: "local://comic"),
            book(id: "text", title: "小说", sourceURL: "https://text.invalid")
        ]
        let result = ShelfProjection.books(
            books, group: nil, media: "comic", query: "", sort: .title,
            returnOrder: [],
            mediaKind: { candidate in
                if candidate.mediaKind != nil { return candidate.mediaKind }
                if candidate.sourceURL == "local://comic" { return .comic }
                if candidate.sourceURL == "https://comic.invalid" { return .comic }
                return .text
            }
        )
        XCTAssertEqual(result.map(\.id), ["local", "source"])
    }

    func testPinnedBooksLeadWhenNoReturnOrder() {
        let books = [
            book(id: "recent", title: "最近", lastReadAt: Date(timeIntervalSince1970: 200)),
            book(id: "pinned", title: "置顶", isPinned: true),
            book(id: "old", title: "较早", lastReadAt: Date(timeIntervalSince1970: 100))
        ]
        let result = ShelfProjection.books(
            books, group: nil, media: nil, query: "", sort: .recentRead,
            returnOrder: [], mediaKind: { $0.mediaKind }
        )
        XCTAssertEqual(result.map(\.id), ["pinned", "recent", "old"])
    }
}
