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

    private func render(_ book: BookshelfBook, width: CGFloat, waiting: Bool) async throws -> UIImage {
        // ImageRenderer omits ScrollView's UIKit-backed contents. Mount the real
        // hierarchy so a blank image cannot masquerade as an opening-state check.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        let parent = UIViewController()
        window.rootViewController = parent
        window.makeKeyAndVisible()
        let host = UIHostingController(rootView: ReaderOpeningStatus(book: book, showsWait: waiting)
            .environment(\.dynamicTypeSize, .large))
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: 568)
        host.didMove(toParent: parent)
        defer {
            window.isHidden = true
            host.willMove(toParent: nil)
            host.view.removeFromSuperview()
            host.removeFromParent()
            previousWindow?.makeKey()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        host.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.size, CGSize(width: width, height: 568))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: host.view.bounds.size, format: format).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
    }

    func testFirstTransitionFrameAlreadyIdentifiesTheActualBookAtBothWidths() async throws {
        let previous = UserDefaults.standard.object(forKey: "reader.background")
        UserDefaults.standard.set(ReaderBackground.white.rawValue, forKey: "reader.background")
        defer { UserDefaults.standard.set(previous, forKey: "reader.background") }
        for width in [CGFloat(320), CGFloat(390)] {
            let first = try await render(book("第一本真实书名", chapter: "第六章 湖边"), width: width, waiting: false)
            let second = try await render(book("另一部作品", chapter: "第九章 远山"), width: width, waiting: false)
            let attachment = XCTAttachment(image: first)
            attachment.name = "reader-opening-light-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(first.size, CGSize(width: width, height: 568))
            XCTAssertNotEqual(first.pngData(), second.pngData(),
                "Before navigation arrival, the surface must contain this book's context rather than a blank shared screen")
            let again = try await render(book("第一本真实书名", chapter: "第六章 湖边"), width: width, waiting: false)
            XCTAssertEqual(first.pngData(), again.pngData(), "Opening must not substitute random quotations or a time-driven emblem")
        }
    }

    func testBookSpecificDarkPaperIsAlreadyAppliedBeforeTheReaderAppears() async throws {
        let previous = UserDefaults.standard.object(forKey: "reader.background")
        let target = book("opening-dark-" + UUID().uuidString, chapter: "夜读")
        UserDefaults.standard.set(ReaderBackground.white.rawValue, forKey: "reader.background")
        ReaderOverrideStore.shared.setOverride(BookReaderOverride(background: .dark), for: target.id)
        defer {
            UserDefaults.standard.set(previous, forKey: "reader.background")
            ReaderOverrideStore.shared.clearOverride(for: target.id)
        }
        let image = try await render(target, width: 390, waiting: false)
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

    func testWaitingStateAddsProgressWithoutChangingBookContext() async throws {
        let previous = UserDefaults.standard.object(forKey: "reader.background")
        UserDefaults.standard.set(ReaderBackground.white.rawValue, forKey: "reader.background")
        defer { UserDefaults.standard.set(previous, forKey: "reader.background") }
        let target = book("一次有上下文的开卷", chapter: "第三章 重逢")
        let arriving = try await render(target, width: 390, waiting: false)
        let waiting = try await render(target, width: 390, waiting: true)
        XCTAssertEqual(arriving.size, waiting.size)
        XCTAssertNotEqual(arriving.pngData(), waiting.pngData(), "A long load must visibly report progress")
        let crop = CGRect(x: 0, y: 0, width: 390, height: 180)
        let firstHeader = try XCTUnwrap(arriving.cgImage?.cropping(to: crop))
        let nextHeader = try XCTUnwrap(waiting.cgImage?.cropping(to: crop))
        XCTAssertEqual(UIImage(cgImage: firstHeader).pngData(), UIImage(cgImage: nextHeader).pngData(),
            "Showing progress must not move the book title or replace it with a brand graphic")
    }
}
