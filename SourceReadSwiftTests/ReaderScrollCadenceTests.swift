import SwiftUI
import WebKit
import XCTest
@testable import SourceReadSwift

final class ReaderScrollCadenceTests: XCTestCase {
    @MainActor func testPositionOnlyUpdatesDoNotRebuildTypographyOrFontLookup() async throws {
        func fixture(index: Int = -1, size: Double = 20) -> WebScrollReaderView {
            WebScrollReaderView(sections: [.init(chapterIndex: 0, title: "第一章", paragraphs: ["正文"])],
            contentFingerprint: "cadence", fontSize: size, lineSpacing: 8, pagePadding: 20, letterSpacing: 0,
            paragraphSpacing: 12, paragraphIndent: 40, titleSpacing: 12, footerHeight: 40,
            textColor: .black, highlightColor: .yellow, currentParagraphIndex: index, scrollTarget: nil,
            scrollRequestKey: nil, animatedScrollDuration: 0, textSelectionEnabled: false, onVisibleParagraph: { _ in })
        }
        let initial = fixture()
        let coordinator = initial.makeCoordinator(), web = coordinator.makeWebView(initialView: initial)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let previous = scene?.windows.first(where: \.isKeyWindow)
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        let host = UIViewController(); window.rootViewController = host; window.makeKeyAndVisible()
        host.view.addSubview(web); web.frame = CGRect(x: 0, y: 0, width: 390, height: 760)
        defer { coordinator.tearDown(webView: web); window.isHidden = true; previous?.makeKey() }
        for _ in 0..<100 {
            if coordinator.styleBuildCount > 0 { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertGreaterThan(coordinator.styleBuildCount, 0)
        let before = coordinator.styleBuildCount
        for index in 0..<50 { coordinator.update(view: fixture(index: index), webView: web) }
        XCTAssertEqual(coordinator.styleBuildCount, before, "Scroll updates must not repeat font resolution even when the final payload is equal")
        coordinator.update(view: fixture(size: 21), webView: web)
        XCTAssertEqual(coordinator.styleBuildCount, before + 1, "Real typography changes must still reach the document")
    }
}
