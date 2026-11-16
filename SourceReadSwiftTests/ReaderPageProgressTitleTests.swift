import XCTest
@testable import SourceReadSwift

final class ReaderPageProgressTitleTests: XCTestCase {
    func testPrewarmedPagesKeepTheirOwnPageNumbers() {
        let titles = (1...3).map { ordinal in
            ReaderPageProgressTitle.format(chapterIndex: 0, chapterTitle: "第壹章 入门",
                                           totalChapters: 5, pageStatus: "页 \(ordinal)/3")
        }
        XCTAssertEqual(titles, ["第 1 / 5 章 · 20% · 页 1/3", "第 1 / 5 章 · 20% · 页 2/3", "第 1 / 5 章 · 20% · 页 3/3"])
    }

    func testPrewarmedNeighbourChapterUsesItsOwnChapterAndPercentage() {
        XCTAssertEqual(ReaderPageProgressTitle.format(chapterIndex: 1, chapterTitle: "第二章",
                                                     totalChapters: 5, pageStatus: "页 1/4"),
                       "第 2 / 5 章 · 40% · 页 1/4")
    }

    func testPrintedChapterNumberStillTakesPrecedenceOverVolumeOffset() {
        XCTAssertEqual(ReaderPageProgressTitle.format(chapterIndex: 26, chapterTitle: "第25章 地宫全图",
                                                     totalChapters: 100, pageStatus: "页 2/7"),
                       "第 25 / 100 章 · 27% · 页 2/7")
    }

    func testUnknownChapterTotalAndMissingPageCountDoNotInventProgress() {
        XCTAssertEqual(ReaderPageProgressTitle.format(chapterIndex: 3, chapterTitle: "第四章",
                                                     totalChapters: nil, pageStatus: "页 2/3"),
                       "第 4 章 · 页 2/3")
        XCTAssertEqual(ReaderPageProgressTitle.format(chapterIndex: 3, chapterTitle: "第四章",
                                                     totalChapters: 10, pageStatus: nil),
                       "第 4 / 10 章 · 40%")
    }
}
