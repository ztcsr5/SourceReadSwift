import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ForestFollowupTests: XCTestCase {
    func testSheetHeightChangesDoNotKeepRecenteringTheChapterDirectory() throws {
        let chapters = (0..<1009).map {
            BookChapter(title: "第 \($0 + 1) 章", url: "local://sheet/\($0)", bookUrl: "local://sheet", index: $0)
        }
        let host = UIHostingController(rootView: ReaderChapterDirectoryList(
            projection: .init(chapters: chapters, entries: [], currentChapter: 600, upperBound: chapters.count,
                readyChapters: [], canLoadChapter: false),
            location: IndexPath(row: 600, section: 0), locationRequest: UUID(),
            ink: .primary, accent: .green, selectChapter: { _ in }, selectEntry: nil))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        host.view.layoutIfNeeded()
        let table = try XCTUnwrap(findDirectory(in: host.view))
        table.layoutIfNeeded()
        let offset = table.contentOffset.y
        XCTAssertTrue(table.indexPathsForVisibleRows?.contains(IndexPath(row: 600, section: 0)) == true)
        for _ in 0..<12 {
            table.bounds.size.height -= 8
            table.setNeedsLayout()
            table.layoutIfNeeded()
            XCTAssertEqual(table.contentOffset.y, offset, accuracy: 0.5,
                "The sheet owns its drag; directory layout must not issue another scrollToRow")
        }
        XCTAssertLessThan(table.visibleCells.count, 40)
    }

    private func findDirectory(in view: UIView) -> ReaderChapterDirectoryList.DirectoryTable? {
        if let table = view as? ReaderChapterDirectoryList.DirectoryTable { return table }
        for child in view.subviews {
            if let table = findDirectory(in: child) { return table }
        }
        return nil
    }

    func testTintedCardsRespectAccessibilityWithoutChangingOtherThemes() {
        for theme in AppVisualTheme.allCases {
            XCTAssertEqual(theme.glassCardOpacity(reducesTransparency: true, increasedContrast: false), 1)
            XCTAssertEqual(theme.glassCardOpacity(reducesTransparency: false, increasedContrast: true), 1)
            XCTAssertEqual(theme.glassCardOpacity(reducesTransparency: false, increasedContrast: false),
                [.forest, .coverGlass].contains(theme) ? 0.64 : 1)
        }
    }

    func testBackgroundFlushDoesNotInitializeUnusedReadingHistory() async {
        let app = AppState()
        XCTAssertFalse(app.hasLoadedReadingHistory)
        app.finishReadingWritesInBackground()
        await app.bookshelfStore.waitForPendingWrites()
        XCTAssertFalse(app.hasLoadedReadingHistory)
        _ = app.readingHistoryStore
        XCTAssertTrue(app.hasLoadedReadingHistory)
        app.finishReadingWritesInBackground()
        await app.readingHistoryStore.waitForPendingWrites()
    }

    func testDetailReturnDoesNotInstallAModalZoomOverTheOwningBackStack() async throws {
        let defaults = UserDefaults.standard
        let previousStyle = defaults.object(forKey: ReaderNavigationStyle.defaultsKey)
        defaults.set(ReaderNavigationStyle.coverZoom.rawValue, forKey: ReaderNavigationStyle.defaultsKey)
        defer { defaults.set(previousStyle, forKey: ReaderNavigationStyle.defaultsKey) }
        let root = UIViewController()
        let navigation = ReaderNavigationController(rootViewController: root)
        navigation.setNavigationBarHidden(true, animated: false)
        let app = AppState()
        app.readerNavigation.attach(navigation, appState: app)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previousWindow?.makeKey() }
        let control = UIButton(frame: CGRect(x: 32, y: 140, width: 160, height: 44))
        root.view.addSubview(control)
        ReaderZoomSources.shared.register(control, id: "reader|detail-return-fixture")
        let book = BookshelfBook(id: "detail-return-fixture", title: "返回详情", author: "纸间", coverURL: nil,
            sourceName: "本地", sourceURL: "local://text", bookURL: "local://detail-return", intro: nil)
        var returns = 0
        let request = ReaderDestinationRequest(book: book, sourceID: "reader|detail-return-fixture",
            returnsToDetail: true, onReturn: { returns += 1 }) { _ in AnyView(Text("阅读正文")) }
        XCTAssertTrue(app.readerNavigation.open(request))
        let reader = try XCTUnwrap(app.readerNavigation.reader)
        XCTAssertTrue(navigation.topViewController === reader)
        XCTAssertNil(reader.presentingViewController)
        if #available(iOS 18, *) { XCTAssertNil(reader.preferredTransition) }
        for _ in 0..<200 where reader.session.phase != .reading {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        app.readerNavigation.close()
        for _ in 0..<200 where app.readerNavigation.reader != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNil(app.readerNavigation.reader)
        XCTAssertTrue(navigation.topViewController === root)
        XCTAssertNil(navigation.transitionCoordinator)
        XCTAssertEqual(returns, 1)
        let point = control.convert(CGPoint(x: 80, y: 22), to: window)
        XCTAssertTrue(window.hitTest(point, with: nil) === control, "The owner receives taps as soon as return completes")
    }
}
