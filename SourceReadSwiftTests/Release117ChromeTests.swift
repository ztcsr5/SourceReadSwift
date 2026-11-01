import SwiftUI
import WebKit
import XCTest
@testable import SourceReadSwift

final class Release117ChromeTests: XCTestCase {
    func testGlassRequiresBothActualRuntimeAndTransparencyPermission() {
        XCTAssertFalse(ReaderChromeSurface.usesNativeGlass(reduceTransparency: true))
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            XCTAssertTrue(ReaderChromeSurface.usesNativeGlass(reduceTransparency: false))
        } else {
            XCTAssertFalse(ReaderChromeSurface.usesNativeGlass(reduceTransparency: false))
        }
        #else
        XCTAssertFalse(ReaderChromeSurface.usesNativeGlass(reduceTransparency: false))
        #endif
    }

    @MainActor func testReaderChromeOnNarrowPaperAndReducedTransparency() async throws {
        let defaults = UserDefaults.standard
        let keys = ["reader.background", "reader.mode"]
        let old = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, old) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set("scroll", forKey: keys[1])
        let chapter = BookChapter(title: "第七十四章 · 长章节标题与安全边距", url: "https://chrome.invalid/1", bookUrl: "fixture", index: 0)
        let content = ChapterContent(chapter: chapter, title: chapter.title,
            paragraphs: Array(repeating: "真实正文就绪后再截图；顶部标题和系统状态区域不应被正文干扰。", count: 30), nextContentUrl: nil)
        for (width, paper, reduced) in [(CGFloat(320), "white", false), (390, "bamboo", false), (390, "white", true)] {
            defaults.set(paper, forKey: keys[0])
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
            window.frame = UIScreen.main.bounds
            let container = UIViewController()
            let host = UIHostingController(rootView: ReaderView(bookID: "", content: content,
                chapterIndex: 0, totalChapters: 1, initialOverlayVisible: true)
                .environmentObject(AppState()).environment(\.accessibilityReduceTransparency, reduced))
            window.rootViewController = container; window.makeKeyAndVisible()
            container.addChild(host); container.view.addSubview(host.view)
            host.view.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            host.didMove(toParent: container)
            defer { window.isHidden = true }
            func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
            var ready = false
            for _ in 0..<100 {
                if let web = descendants(host.view).compactMap({ $0 as? WKWebView }).first {
                    ready = (try? await web.evaluateJavaScript("document.body.innerText.includes('真实正文就绪')")) as? Bool == true
                }
                if ready { break }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            XCTAssertTrue(ready)
            host.view.layoutIfNeeded()
            let more = try XCTUnwrap(descendants(host.view).first { $0.accessibilityIdentifier == "reader.more" })
            let rect = more.convert(more.bounds, to: host.view)
            XCTAssertGreaterThanOrEqual(rect.minX, 16)
            XCTAssertLessThanOrEqual(rect.maxX, width - 16)
            XCTAssertGreaterThanOrEqual(rect.height, 44)
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "release117-reader-chrome-\(Int(width))-\(paper)-reduced-\(reduced)"
            attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
