import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import SourceReadSwift

@MainActor
final class ReaderNativeNavigationTests: XCTestCase {
    func testRealReaderPushAndPopRetainTheRootAndDoNotOwnTabChrome() async throws {
        let app = AppState()
        let root = UIHostingController(rootView: RootTabView().environmentObject(app))
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        app.readerNavigation.attach(navigation, appState: app)
        let previous = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let scene = previous?.windowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
        window.frame = UIScreen.main.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let mounted = await eventually { root.view.window != nil }
        XCTAssertTrue(mounted)
        let rootIdentity = ObjectIdentifier(root)
        var book = BookshelfBook(id: "native-navigation-fixture", title: "导航测试", author: "",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://navigation", intro: nil)
        book.localContent = (0..<50).map { "第\($0)段。阅读器必须保留真实 WebView 与阅读位置。" }
        XCTAssertTrue(app.readerNavigation.open(.shelf(book)))
        let reader = try XCTUnwrap(app.readerNavigation.reader)
        let ready = await eventually { reader.session.webViewIdentities.count == 1 && reader.session.phase == .reading }
        XCTAssertTrue(ready)
        XCTAssertEqual(reader.session.shellLoads, 1)
        XCTAssertFalse(app.isTabChromeHidden, "The retained root bar must not participate in reader ownership")
        XCTAssertTrue(app.isReaderPresented)
        XCTAssertFalse(app.readerNavigation.open(.shelf(book)), "A duplicate tap cannot create a second reader")
        XCTAssertTrue(reader === app.readerNavigation.reader)
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil && navigation.topViewController === root }
        XCTAssertTrue(returned)
        XCTAssertEqual(ObjectIdentifier(navigation.viewControllers[0]), rootIdentity)
        XCTAssertEqual(reader.session.phase, .closed)
        XCTAssertFalse(app.isReaderPresented)
        XCTAssertFalse(app.isTabChromeHidden)
    }

    private func eventually(_ predicate: @escaping () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }
}
