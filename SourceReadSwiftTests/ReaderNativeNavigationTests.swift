import XCTest
import SwiftUI
import UIKit
import WebKit
@testable import SourceReadSwift

@MainActor
final class ReaderNativeNavigationTests: XCTestCase {
    func testAppHostingBoundaryUsesTheWindowAndRevealsPositionedProse() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
        let app = AppState()
        let outer = UIHostingController(rootView: ReaderNavigationHost().ignoresSafeArea().environmentObject(app))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = outer
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let mounted = await eventually { self.findNavigation(outer) != nil }
        XCTAssertTrue(mounted)
        let navigation = try XCTUnwrap(findNavigation(outer))
        XCTAssertEqual(navigation.view.convert(navigation.view.bounds, to: window), window.bounds,
                       "The representable must not inset the UIKit navigation before UIKit applies its safe area")
        var book = BookshelfBook(id: "app-host-fixture", title: "真实容器", author: "",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://app-host", intro: nil)
        book.localContent = (0..<60).map { "正文第\($0)段。应用容器边界必须保留正文、定位与原生返回。" }
        book.currentChapterIndex = 0
        book.currentParagraphIndex = 30
        XCTAssertTrue(app.readerNavigation.open(.shelf(book)))
        let reader = try XCTUnwrap(app.readerNavigation.reader)
        let ready = await eventually { reader.session.hasPresentedContent }
        XCTAssertTrue(ready, "The full application hosting boundary must receive the actual WebKit render acknowledgement; stage=\(reader.session.openingStage) managed=\(reader.session.isOpeningManaged) appearances=\(reader.session.readerAppearances)")
        XCTAssertEqual(reader.session.webViewIdentities.count, 1)
        XCTAssertEqual(reader.session.shellLoads, 1)
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil }
        XCTAssertTrue(returned)
        XCTAssertEqual(navigation.viewControllers.count, 1)
    }

    func testRealReaderPushAndPopRetainTheRootAndDoNotOwnTabChrome() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
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
        let ready = await eventually { reader.session.webViewIdentities.count == 1
            && reader.session.hasPresentedContent && reader.session.phase == .reading }
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

    func testReaderOpenedFromASheetReturnsToThatSameSheet() async throws {
        let previousMode = UserDefaults.standard.object(forKey: "reader.mode")
        UserDefaults.standard.set("scroll", forKey: "reader.mode")
        defer { UserDefaults.standard.set(previousMode, forKey: "reader.mode") }
        let app = AppState()
        let root = UIHostingController(rootView: RootTabView().environmentObject(app))
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        app.readerNavigation.attach(navigation, appState: app)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        let sheet = UIHostingController(rootView: ReaderBookmarksView().environmentObject(app))
        sheet.modalPresentationStyle = .pageSheet
        navigation.present(sheet, animated: false)
        let mounted = await eventually { sheet.view.window != nil }
        XCTAssertTrue(mounted)
        var book = BookshelfBook(id: "sheet-native-fixture", title: "目录继续阅读", author: "",
            coverURL: nil, sourceName: "本地", sourceURL: "local://text", bookURL: "local://sheet", intro: nil)
        book.localContent = ["从已有的目录或者书签面板进入，退出后保留原面板。"]
        XCTAssertTrue(app.readerNavigation.open(.shelf(book)))
        let reader = try XCTUnwrap(app.readerNavigation.reader)
        let ready = await eventually { reader.session.phase == .reading && reader.session.shellLoads == 1
            && reader.session.hasPresentedContent }
        XCTAssertTrue(ready)
        XCTAssertTrue(reader.presentingViewController === sheet)
        XCTAssertEqual(navigation.viewControllers.count, 1)
        app.readerNavigation.close()
        let returned = await eventually { app.readerNavigation.reader == nil && sheet.presentedViewController == nil }
        XCTAssertTrue(returned)
        XCTAssertTrue(navigation.presentedViewController === sheet)
        XCTAssertTrue(sheet.view.window === window)
        XCTAssertFalse(app.isReaderPresented)
        navigation.dismiss(animated: false)
    }

    private func eventually(_ predicate: @escaping () -> Bool) async -> Bool {
        for _ in 0..<300 {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return predicate()
    }

    private func findNavigation(_ controller: UIViewController) -> ReaderNavigationController? {
        if let navigation = controller as? ReaderNavigationController { return navigation }
        for child in controller.children {
            if let navigation = findNavigation(child) { return navigation }
        }
        return nil
    }
}
