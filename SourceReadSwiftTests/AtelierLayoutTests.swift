import SwiftUI
import XCTest
@testable import SourceReadSwift

final class AtelierLayoutTests: XCTestCase {
    func testNoAtelierThemePaintsNoninteractiveMarksAcrossPagesOrCards() {
        for theme in AppVisualTheme.atelierThemes {
            XCTAssertFalse(AppThemeOrnament.hasArtwork(theme: theme, isCard: false), theme.rawValue)
            XCTAssertFalse(AppThemeOrnament.hasArtwork(theme: theme, isCard: true), theme.rawValue)
            XCTAssertFalse(theme.usesFramedShelf, theme.rawValue)
        }
        XCTAssertTrue(AppVisualTheme.anime.usesFramedShelf)
        XCTAssertTrue(AppThemeOrnament.hasArtwork(theme: .shuimo, isCard: true))
        XCTAssertEqual(AppVisualTheme.initialSelection, .forest)
    }

    func testProgressRailMatchesUnreadUnknownAndClampedChapterSemantics() throws {
        var book = makeBook()
        XCTAssertEqual(try XCTUnwrap(AtelierReadingProgress.fraction(for: book)), 0.64, accuracy: 0.001)
        book.lastReadAt = nil
        XCTAssertNil(AtelierReadingProgress.fraction(for: book))
        XCTAssertEqual(ReadingHeroStatus.progressValue(for: book), "待开始")
        book.lastReadAt = Date(timeIntervalSince1970: 1)
        book.totalChapters = 0
        XCTAssertNil(AtelierReadingProgress.fraction(for: book))
        book.totalChapters = -1
        XCTAssertNil(AtelierReadingProgress.fraction(for: book))
        book.totalChapters = 100
        book.currentChapterIndex = Int.max
        XCTAssertEqual(AtelierReadingProgress.fraction(for: book), 1)
        book.currentChapterIndex = Int.min
        XCTAssertEqual(AtelierReadingProgress.fraction(for: book), 0.01)
    }

    @MainActor func testEveryReadingCardReclaimsHeightWithoutOverflowAt320And390Points() {
        let previous = UserDefaults.standard.object(forKey: AppVisualTheme.selectionKey)
        defer { restoreTheme(previous) }
        for theme in AppVisualTheme.atelierThemes {
            UserDefaults.standard.set(theme.rawValue, forKey: AppVisualTheme.selectionKey)
            for width: CGFloat in [288, 358] {
                let size = measure(theme: theme, width: width, type: .large)
                XCTAssertEqual(size.width, width, accuracy: 1, theme.rawValue)
                XCTAssertLessThanOrEqual(size.height, 260, "\(theme.rawValue): compact cards must leave room for the shelf")
                XCTAssertGreaterThan(size.height, 160, "The cover and metadata must not collapse")
            }
        }
    }

    @MainActor func testAccessibleTitlesGrowVerticallyInsteadOfBeingClipped() {
        let previous = UserDefaults.standard.object(forKey: AppVisualTheme.selectionKey)
        defer { restoreTheme(previous) }
        for theme in AppVisualTheme.atelierThemes {
            UserDefaults.standard.set(theme.rawValue, forKey: AppVisualTheme.selectionKey)
            let normal = measure(theme: theme, width: 288, type: .large)
            let accessible = measure(theme: theme, width: 288, type: .accessibility3)
            XCTAssertEqual(accessible.width, 288, accuracy: 1, theme.rawValue)
            XCTAssertGreaterThan(accessible.height, normal.height + 100, theme.rawValue)
        }
    }

    @MainActor private func measure(theme: AppVisualTheme, width: CGFloat, type: DynamicTypeSize) -> CGSize {
        UIHostingController(rootView: AtelierCardFixture(book: makeBook(), theme: theme)
            .environment(\.dynamicTypeSize, type))
            .sizeThatFits(in: CGSize(width: width, height: 6000))
    }

    private func restoreTheme(_ previous: Any?) {
        if let previous { UserDefaults.standard.set(previous, forKey: AppVisualTheme.selectionKey) }
        else { UserDefaults.standard.removeObject(forKey: AppVisualTheme.selectionKey) }
    }

    private func makeBook() -> BookshelfBook {
        var book = BookshelfBook(id: "atelier-long-title", title: "白昼之后，我们把很长很长的信写给远方与尚未相逢的人",
            author: "一位名字也非常长的作者", coverURL: nil, sourceName: "离线验收", sourceURL: "local://text",
            bookURL: "local://atelier", intro: nil)
        book.lastReadAt = Date(timeIntervalSince1970: 1)
        book.totalChapters = 100
        book.currentChapterIndex = 63
        book.currentChapterTitle = "第六十四章 · 写给下一页的信"
        return book
    }
}

private struct AtelierCardFixture: View {
    let book: BookshelfBook
    let theme: AppVisualTheme
    @Namespace private var heroNamespace

    var body: some View {
        ThemedReadingCard(book: book, theme: theme, heroNamespace: heroNamespace)
    }
}
