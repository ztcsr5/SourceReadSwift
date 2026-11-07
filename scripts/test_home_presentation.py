"""Guard the revised home interactions; run with unittest discovery from scripts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HomePresentationTests(unittest.TestCase):
    def test_reading_entry_keeps_tap_and_restores_native_long_press_actions(self):
        source = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        card = source.split('private func heroCard', 1)[1].split('private func updateRow', 1)[0]
        self.assertIn('.contextMenu', card)
        self.assertNotIn('private func readingDeskMenu', card)
        self.assertIn('contextualBookRoute = .read(book, coverFrame:', card)
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


if __name__ == '__main__':
    unittest.main()
