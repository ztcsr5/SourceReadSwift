import SwiftUI
import WebKit
import XCTest
@testable import SourceReadSwift

final class Release117DetailTests: XCTestCase {
    @MainActor func testLocalDetailsRenderWithoutRecursivelyMountingReader() async throws {
        let local = LocalTextBook(title: "指点考古队，竟被当成盗墓贼 · 长标题排版检查", author: "小猴子 yyds",
            chapters: (0..<1009).map { LocalTextChapter(title: "第\($0 + 1)章 章节标题", paragraphs: ["正文"], index: $0) },
            language: "zh-CN")
        let book = BookshelfBook(localTextBook: local)
        for width: CGFloat in [320, 390] {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            let container = UIViewController()
            let host = UIHostingController(rootView: NavigationStack {
                LocalBookMetadataView(book: book, onSelectChapter: { _ in })
            })
            window.rootViewController = container
            window.makeKeyAndVisible()
            container.addChild(host); container.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            host.didMove(toParent: container)
            try await Task.sleep(nanoseconds: 400_000_000)
            host.view.layoutIfNeeded()
            func webCount(_ view: UIView) -> Int {
                (view is WKWebView ? 1 : 0) + view.subviews.reduce(0) { $0 + webCount($1) }
            }
            XCTAssertEqual(webCount(host.view), 0, "Detail must not create a nested reader")
            XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "release117-local-details-\(Int(width))"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }
}
