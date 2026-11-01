import SwiftUI
import UIKit
import XCTest
@testable import SourceReadSwift

final class ReadingNotesNavigationTests: XCTestCase {
    func testOriginalCatalogIsUniqueShortAndDeterministicallySelectable() {
        let notes = ReadingNoteCatalog.all
        XCTAssertEqual(notes.count, 48)
        XCTAssertEqual(Set(notes).count, notes.count)
        XCTAssertTrue(notes.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 36 })
        var a = NoteTestGenerator(), b = NoteTestGenerator()
        let first = (0..<4000).map { _ in ReadingNoteCatalog.choose(using: &a) }
        let second = (0..<4000).map { _ in ReadingNoteCatalog.choose(using: &b) }
        XCTAssertEqual(first, second)
        XCTAssertEqual(Set(first), Set(notes), "Selection must reach the whole catalog, not only its first few entries")
    }

    func testLaunchNoteDoesNotShuffleOnRepeatedReads() {
        let initial = ReadingNoteCatalog.launchNote
        XCTAssertTrue(ReadingNoteCatalog.all.contains(initial))
        for _ in 0..<1000 { XCTAssertEqual(ReadingNoteCatalog.launchNote, initial) }
    }

    func testSharedDiscoveryLabelAndBothBookSymbolStatesExist() {
        XCTAssertEqual(AppNavigationLabels.findBooks, "寻书")
        XCTAssertEqual(AppNavigationLabels.findBooksSymbol, "books.vertical")
        XCTAssertNotNil(UIImage(systemName: AppNavigationLabels.findBooksSymbol))
        XCTAssertNotNil(UIImage(systemName: AppNavigationLabels.findBooksSymbol + ".fill"))
    }

    @MainActor func testCompactBrandNoteAndLegacyBookNavigationAtNarrowWidths() async throws {
        let longest = try XCTUnwrap(ReadingNoteCatalog.all.max { $0.count < $1.count })
        for width: CGFloat in [320, 390] {
            for largeText in [false, true] {
                let content = VStack(spacing: 16) {
                    SettingsBrandHeader(readingNote: longest)
                        .padding(.horizontal, 16)
                    Spacer(minLength: 4)
                    LegacyTabBar(selection: .constant(1), onSearch: {})
                }
                .padding(.top, 16)
                .background(AppTheme.background)
                .dynamicTypeSize(largeText ? .accessibility3 : .large)
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: UIScreen.main.bounds)
                window.frame = UIScreen.main.bounds
                let container = UIViewController(), host = UIHostingController(rootView: content)
                window.rootViewController = container; window.makeKeyAndVisible()
                container.addChild(host); container.view.addSubview(host.view)
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: largeText ? 340 : 210)
                host.didMove(toParent: container)
                try await Task.sleep(nanoseconds: 150_000_000)
                host.view.layoutIfNeeded()
                XCTAssertEqual(host.view.bounds.width, width, accuracy: 1)
                let header = UIHostingController(rootView: SettingsBrandHeader(readingNote: longest)
                    .dynamicTypeSize(largeText ? .accessibility3 : .large))
                let size = header.sizeThatFits(in: CGSize(width: width - 32, height: 600))
                XCTAssertLessThanOrEqual(size.width, width - 31)
                XCTAssertLessThan(size.height, largeText ? 260 : 120, "Header width=\(width), accessibility=\(largeText): retain compact layout and full scalable text")
                let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "release117-settings-note-findbooks-\(Int(width))-\(largeText ? "accessibility" : "standard")"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true
            }
        }
    }
}

private struct NoteTestGenerator: RandomNumberGenerator {
    var state: UInt64 = 0xA715_1E16
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
