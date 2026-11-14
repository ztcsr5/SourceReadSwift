import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

@MainActor
final class ReaderStage139Tests: XCTestCase {
    func testNativeDirectoryMountsOnDistantChapterWithoutMeasuringPrecedingRows() throws {
        let chapters = (0..<1_361).map {
            BookChapter(title: "第 \($0 + 1) 章", url: "local://test/\($0)", bookUrl: "local://test", index: $0)
        }
        let chapterIndex = 868
        let host = UIHostingController(rootView: ReaderChapterDirectoryList(
            projection: .init(chapters: chapters, entries: [], currentChapter: chapterIndex,
                upperBound: chapters.count, readyChapters: [], canLoadChapter: false),
            location: IndexPath(row: chapterIndex, section: 0), locationRequest: UUID(),
            ink: .primary, accent: .green, selectChapter: { _ in }, selectEntry: nil))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let prior = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; prior?.makeKey() }
        host.view.layoutIfNeeded()
        let table = try XCTUnwrap(findDirectory(in: host.view))
        table.layoutIfNeeded()
        let current = IndexPath(row: chapterIndex, section: 0)
        XCTAssertTrue(table.indexPathsForVisibleRows?.contains(current) == true)
        XCTAssertGreaterThan(table.contentOffset.y, 35_000)
        XCTAssertLessThan(table.visibleCells.count, 40,
            "The view must reuse cells; jumping to a far chapter must not mount hundreds of rows")
        XCTAssertEqual(table.cellForRow(at: current)?.accessibilityValue, "当前章")
    }

    func testPersonalBrandMarkCanReloadPreparedPhotoAndRemoveOnlyItsCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            if FileManager.default.fileExists(atPath: directory.path) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        let fixture = UIGraphicsImageRenderer(size: CGSize(width: 90, height: 40)).image { context in
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 90, height: 40))
        }
        let bytes = try XCTUnwrap(fixture.pngData())
        let store = PersonalBrandMarkStore(directory: directory)
        try await store.savePhoto(bytes)
        XCTAssertEqual(store.image?.size, CGSize(width: 512, height: 512))

        let reloaded = PersonalBrandMarkStore(directory: directory)
        await reloaded.loadIfNeeded()
        XCTAssertEqual(reloaded.image?.size, CGSize(width: 512, height: 512))
        do {
            try await reloaded.savePhoto(Data("not an image".utf8))
            XCTFail("Invalid import must not overwrite the stored image")
        } catch PersonalBrandMarkStore.Failure.invalidPhoto {
            XCTAssertNotNil(reloaded.image)
        }
        try await reloaded.removePhoto()
        let cleared = PersonalBrandMarkStore(directory: directory)
        await cleared.loadIfNeeded()
        XCTAssertNil(cleared.image)
    }

    func testOldPreferencesKeepSystemReturnAndFourCoreThemes() {
        XCTAssertEqual(ReaderNavigationStyle.resolve("invalid-legacy-style"), .system)
        XCTAssertFalse(ReaderNavigationStyle.system.providesAnimator)
        XCTAssertTrue(ReaderNavigationStyle.paperFold.providesAnimator)
        XCTAssertTrue(ReaderNavigationStyle.fade.providesAnimator)
        for core in AppVisualTheme.whitelistedCoreThemes {
            XCTAssertNil(AtmosphericThemeSignature(theme: core))
        }
        for atmosphere in AppVisualTheme.atmosphericThemes {
            XCTAssertNotNil(AtmosphericThemeSignature(theme: atmosphere))
            XCTAssertNotEqual(atmosphere.atmosphericPaperAsset(isDark: false), atmosphere.atmosphericPaperAsset(isDark: true))
        }
    }

    private func findDirectory(in view: UIView) -> ReaderChapterDirectoryList.DirectoryTable? {
        if let table = view as? ReaderChapterDirectoryList.DirectoryTable { return table }
        for child in view.subviews {
            if let table = findDirectory(in: child) { return table }
        }
        return nil
    }
}
