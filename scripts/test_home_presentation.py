"""Guard the revised home interactions; run with unittest discovery from scripts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HomePresentationTests(unittest.TestCase):
    def test_classic_and_legacy_settings_share_the_original_desk(self):
        presentation = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookPresentation.swift').read_text(encoding='utf8')
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        self.assertIn('static let initialSelection: Self = .classic', presentation)
        self.assertIn('self == .classic || self == .current', presentation)
        section = shelf.split('private var readingSection:', 1)[1].split('private func homeBookCover', 1)[0]
        self.assertIn('if !homeBookPresentation.usesClassicDesk', section)
        self.assertIn('else if homeBookPresentation.usesClassicDesk', section)
        self.assertIn('ReadingDeskPager(', section)
        appearance = (ROOT / 'SourceReadSwift/Features/Settings/AppearanceSettingsView.swift').read_text(encoding='utf8')
        self.assertIn('presentation.usesClassicDesk ? HomeBookPresentation.classic.rawValue : presentation.rawValue', appearance)

    def test_reference_modes_do_not_duplicate_the_display_or_its_page_insets(self):
        display = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookDisplay.swift').read_text(encoding='utf8')
        self.assertNotIn('ViewThatFits', display)
        self.assertNotIn('.id(style)', display)
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        section = shelf.split('private var readingSection:', 1)[1].split('private func homeBookCover', 1)[0]
        self.assertIn('.padding(.horizontal, -AppTheme.pagePadding)', section)

    def test_horizontal_shelf_keeps_its_full_intrinsic_height(self):
        display = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookDisplay.swift').read_text(encoding='utf8')
        shelf = display.split('private func shelf(isSpine:', 1)[1].split('private func heading', 1)[0]
        scroll = shelf.split('ScrollView(.horizontal', 1)[1].split('.accessibilityIdentifier("home.books.horizontalShelf")', 1)[0]
        self.assertNotIn('.frame(height:', scroll)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', shelf)
        entry = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        self.assertIn('HomeBookSpine(book: book, width: width, height: height)', entry)

    def test_cover_backdrop_belongs_to_page_not_a_rectangular_section(self):
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        backdrop = shelf.split('private var bookshelfBackdrop:', 1)[1].split('private var shelfChromeReveal:', 1)[0]
        self.assertIn('HomeShowcaseBackdrop(', backdrop)
        display = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookDisplay.swift').read_text(encoding='utf8')
        self.assertNotIn('showcaseBackdrop', display)
        self.assertNotIn('.drawingGroup', display)

    def test_reading_entry_keeps_tap_and_restores_native_long_press_actions(self):
        source = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        card = source.split('private func heroCard', 1)[1].split('private func updateRow', 1)[0]
        self.assertIn('.contextMenu', card)
        self.assertNotIn('private func readingDeskMenu', card)
        self.assertIn('readerNavigation.open(.shelf(book, sourceID:', card)
        self.assertIn('bookToRemove = book', card)
        self.assertIn('readingDeskBookActions(book)', card)

    def test_filters_are_collapsed_without_discarding_the_selected_query(self):
        source = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        self.assertIn('@State private var showsShelfFilters = false', source)
        self.assertIn('if !allBooks.isEmpty, showsShelfFilters', source)
        header = source.split('private var shelfHeader:', 1)[1].split('private func mainGroupChip', 1)[0]
        self.assertLess(header.index('bookshelf.filters'), header.index('BookshelfSortMode.allCases'))
        self.assertIn('bookshelf.filterQuery', source)
        tab_bar = (ROOT / 'SourceReadSwift/Shared/DesignSystem/LegacyTabBar.swift').read_text(encoding='utf8')
        self.assertIn('bookshelf.globalSearch', tab_bar)

    def test_shelf_cover_has_one_fixed_book_silhouette(self):
        source = (ROOT / 'SourceReadSwift/Features/Bookshelf/ShelfBookCover.swift').read_text(encoding='utf8')
        self.assertIn('ShelfCoverGeometry.size', source)
        self.assertIn('EditorialBookJacket', source)
        self.assertIn('contentMode: .fill', source)
        self.assertNotIn('contentMode: .fit', source)

    def test_large_text_evidence_reaches_the_offscreen_shelf(self):
        source = (ROOT / 'SourceReadSwiftTests/HomeLayoutEvidenceTests.swift').read_text(encoding='utf8')
        self.assertIn('if accessible { try await attachScrolledLayouts', source)
        self.assertIn('Evidence must reach the final shelf row', source)
        self.assertIn('animated: false', source)

    def test_theme_evidence_is_batched_without_omitting_any_theme(self):
        source = (ROOT / 'SourceReadSwiftTests/HomeLayoutEvidenceTests.swift').read_text(encoding='utf8')
        for group in ('coreThemes', 'atmosphericThemes', 'customThemes'):
            self.assertIn(f'try await captureHomeLayouts(themes: Self.{group})', source)
        self.assertIn('testHomeEvidenceGroupsCoverEveryRequestedThemeExactlyOnce', source)
        self.assertIn('AppVisualTheme.allCases', source)
        self.assertIn('XCTAssertEqual(grouped.map', source)


if __name__ == '__main__':
    unittest.main()
