import XCTest
@testable import SourceReadSwift

@MainActor
final class OnboardingClassicBookTests: XCTestCase {
    func testOnboardingClassicBookStructure() {
        let book = OnboardingClassicBook.makeWelcomeBook()
        XCTAssertEqual(book.title, "纸间·阅读指引与经典选篇")
        XCTAssertEqual(book.author, "纸间团队")
        XCTAssertEqual(book.publisher, "纸间 InPage")
        XCTAssertEqual(book.language, "zh-CN")
        XCTAssertEqual(book.chapters.count, 5)

        XCTAssertTrue(book.chapters[0].title.contains("纸间入门指南"))
        XCTAssertTrue(book.chapters[1].title.contains("从百草园到三味书屋"))
        XCTAssertTrue(book.chapters[2].title.contains("荷塘月色"))
        XCTAssertTrue(book.chapters[3].title.contains("故乡"))
        XCTAssertTrue(book.chapters[4].title.contains("本地优先隐私协议"))

        for chapter in book.chapters {
            XCTAssertFalse(chapter.title.isEmpty)
            XCTAssertFalse(chapter.paragraphs.isEmpty)
        }
        XCTAssertGreaterThan(book.paragraphs.count, 20)
    }

    func testBookshelfStoreSeedsOnboardingBook() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = BookshelfStore(persistence: BookshelfPersistence(fileManager: .default, rootURL: root))
        XCTAssertEqual(store.books.count, 0)

        // Seed with force: true
        store.seedOnboardingBookIfNeeded(force: true)
        XCTAssertEqual(store.books.count, 1)
        XCTAssertEqual(store.books.first?.title, "纸间·阅读指引与经典选篇")
        XCTAssertEqual(store.books.first?.author, "纸间团队")
        XCTAssertEqual(store.books.first?.totalChapters, 5)

        // Ensure subsequent call does not duplicate
        store.seedOnboardingBookIfNeeded(force: false)
        XCTAssertEqual(store.books.count, 1)
    }

    func testReaderSpeechQueueNavigation() {
        var queue = ReaderSpeechQueue()
        queue.reset(
            title: "测试章节",
            paragraphs: ["第一段正文", "第二段正文", "第三段正文"],
            startParagraphIndex: 0,
            includeTitle: true
        )

        XCTAssertEqual(queue.totalSegments, 4)
        XCTAssertEqual(queue.currentSegmentPosition, 0)

        let seg0 = queue.dequeue()
        XCTAssertEqual(seg0?.index, -1)
        XCTAssertEqual(seg0?.text, "测试章节")
        XCTAssertEqual(queue.currentSegmentPosition, 1)

        let seg1 = queue.dequeue()
        XCTAssertEqual(seg1?.index, 0)
        XCTAssertEqual(seg1?.text, "第一段正文")
        XCTAssertEqual(queue.currentSegmentPosition, 2)

        // Step back
        let stepped = queue.stepBack()
        XCTAssertEqual(stepped?.index, -1)
        XCTAssertEqual(stepped?.text, "测试章节")
        XCTAssertEqual(queue.currentSegmentPosition, 1)
    }
}
