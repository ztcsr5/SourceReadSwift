import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderOpeningTransitionTests: XCTestCase {
    private func book(_ title: String, chapter: String) -> BookshelfBook {
        var book = BookshelfBook(id: title, title: title, author: "测试作者", coverURL: nil,
            sourceName: "本地", sourceURL: "local://text", bookURL: "local://opening", intro: nil)
        book.currentChapterTitle = chapter
        book.currentParagraphIndex = 12
        return book
    }

    private func render(_ book: BookshelfBook, width: CGFloat, waiting: Bool) throws -> UIImage {
        let renderer = ImageRenderer(content: ReaderOpeningStatus(book: book, showsWait: waiting)
            .frame(width: width, height: 568))
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    func testFirstTransitionFrameAlreadyIdentifiesTheActualBookAtBothWidths() throws {
        let previous = UserDefaults.standard.object(forKey: "reader.background")
        UserDefaults.standard.set(ReaderBackground.white.rawValue, forKey: "reader.background")
        defer { UserDefaults.standard.set(previous, forKey: "reader.background") }
        for width in [CGFloat(320), CGFloat(390)] {
            let first = try render(book("第一本真实书名", chapter: "第六章 湖边"), width: width, waiting: false)
            let second = try render(book("另一部作品", chapter: "第九章 远山"), width: width, waiting: false)
            let attachment = XCTAttachment(image: first)
            attachment.name = "reader-opening-light-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(first.size, CGSize(width: width, height: 568))
            XCTAssertNotEqual(first.pngData(), second.pngData(),
                "Before navigation arrival, the surface must contain this book's context rather than a blank shared screen")
            let again = try render(book("第一本真实书名", chapter: "第六章 湖边"), width: width, waiting: false)
            XCTAssertEqual(first.pngData(), again.pngData(), "Opening must not substitute random quotations or a time-driven emblem")
        }
    }

    func testBookSpecificDarkPaperIsAlreadyAppliedBeforeTheReaderAppears() throws {
        let previous = UserDefaults.standard.object(forKey: "reader.background")
        let target = book("opening-dark-" + UUID().uuidString, chapter: "夜读")
        UserDefaults.standard.set(ReaderBackground.white.rawValue, forKey: "reader.background")
        ReaderOverrideStore.shared.setOverride(BookReaderOverride(background: .dark), for: target.id)
        defer {
            UserDefaults.standard.set(previous, forKey: "reader.background")
            ReaderOverrideStore.shared.clearOverride(for: target.id)
        }
        let image = try render(target, width: 390, waiting: false)
        let attachment = XCTAttachment(image: image)
        attachment.name = "reader-opening-book-dark-390"
        attachment.lifetime = .keepAlways
        add(attachment)
        let cgImage = try XCTUnwrap(image.cgImage)
        var rgba = [UInt8](repeating: 0, count: 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        try rgba.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: -4, y: -4, width: 390, height: 568))
        }
        XCTAssertEqual(rgba, [0, 0, 0, 255], "A saved dark book must not flash the global white paper during opening")
    }

    func testWaitingStateAddsProgressWithoutChangingBookContext() throws {
        let previous = UserDefaults.standard.object(forKey: "reader.background")
        UserDefaults.standard.set(ReaderBackground.white.rawValue, forKey: "reader.background")
        defer { UserDefaults.standard.set(previous, forKey: "reader.background") }
        let target = book("一次有上下文的开卷", chapter: "第三章 重逢")
        let arriving = try render(target, width: 390, waiting: false)
        let waiting = try render(target, width: 390, waiting: true)
        XCTAssertEqual(arriving.size, waiting.size)
        XCTAssertNotEqual(arriving.pngData(), waiting.pngData(), "A long load must visibly report progress")
        let crop = CGRect(x: 0, y: 0, width: 390, height: 180)
        let firstHeader = try XCTUnwrap(arriving.cgImage?.cropping(to: crop))
        let nextHeader = try XCTUnwrap(waiting.cgImage?.cropping(to: crop))
        XCTAssertEqual(UIImage(cgImage: firstHeader).pngData(), UIImage(cgImage: nextHeader).pngData(),
            "Showing progress must not move the book title or replace it with a brand graphic")
    }
}
