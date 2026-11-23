"""Guard the revised home interactions; run with unittest discovery from scripts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HomePresentationTests(unittest.TestCase):
    def test_showcase_progress_reuses_the_bounded_unread_and_extreme_index_rules(self):
        display = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookDisplay.swift').read_text(encoding='utf8')
        rail = display.split('private func progressRail', 1)[1].split('private func mediaIcon', 1)[0]
        self.assertTrue('AtelierReadingProgress.fraction(for: book)' in rail)
        self.assertNotIn('book.readingProgress', rail)

    def test_ui_checks_both_precise_preview_selection_and_multibook_fling(self):
        ui = (ROOT / 'SourceReadSwiftUITests/AtelierHomeUITests.swift').read_text(encoding='utf8')
        self.assertIn('testFastFlingCanCrossMultipleBooksInClassicAndShowcase', ui)
        self.assertIn('pager.swipeLeft(velocity: .fast)', ui)
        self.assertIn('withVelocity: .slow', ui)
        fling = ui.split('func testFastFlingCanCrossMultipleBooks', 1)[1].split('private func dragOneBook', 1)[0]
        self.assertNotIn('thenHoldForDuration', fling)
        self.assertEqual(ui.count('dragOneBook(in: pager)'), 2)
        self.assertIn('currentBook(app, title: "月亮与六便士")', ui)
        self.assertIn('XCTAssertEqual(filters.frame.midY, originalY, accuracy: 2)', ui)
        self.assertIn('XCTAssertEqual(third.frame.midX, pager.frame.midX, accuracy: 24', ui)

    def test_paper_theme_has_an_explicit_ambient_preset(self):
        source = (ROOT / 'SourceReadSwift/Core/Audio/HttpTTSVoiceStore.swift').read_text(encoding='utf8')
        recommendation = source.split('static func recommended(for visualTheme:', 1)[1].split('var filterParameters:', 1)[0]
        self.assertRegex(recommendation, r'case [\w., ]*\.paper[\w., ]*: return \.paperWind')
        self.assertRegex(recommendation, r'case [\w., ]*\.forest[\w., ]*: return \.rain')

    def test_classic_and_legacy_settings_share_the_original_desk(self):
        presentation = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookPresentation.swift').read_text(encoding='utf8')
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        self.assertIn('isExistingInstall ? Self.classic : Self.showcase', presentation)
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

    def test_removed_modes_and_duplicate_journal_strip_are_not_rendered(self):
        presentation = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookPresentation.swift').read_text(encoding='utf8')
        self.assertIn('static let allCases: [Self] = [.showcase, .journal, .classic, .shelfRow]', presentation)
        self.assertIn('case .sculptural, .magazine, .library: return .classic', presentation)
        display = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookDisplay.swift').read_text(encoding='utf8')
        for removed in ['private func shelf(', 'compactCard(', 'books.dropFirst()', 'sculpturalMetadata(']:
            self.assertNotIn(removed, display)
        metadata = display.split('private func showcaseMetadata(', 1)[1].split('private func progressRail', 1)[0]
        self.assertNotIn('bookAction(', metadata)
        self.assertNotIn('Circle()', metadata)
        self.assertIn('frame(width: 110)', metadata)
        self.assertIn('.title2.weight(.bold)', metadata)

    def test_shelf_row_is_opt_in_and_does_not_duplicate_the_library(self):
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        row = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeShelfRow.swift').read_text(encoding='utf8')
        self.assertIn('if homeBookPresentation != .shelfRow { shelfSection }', shelf)
        self.assertIn('BookshelfCollectionView(title: "书架", books: allBooks', shelf)
        self.assertIn('Text("手边的书")', row)
        self.assertIn('AppPagePaper(theme: theme)', row)
        self.assertIn('AtelierReadingProgress.fraction(for: book)', row)
        self.assertNotIn('.blur(', row)

    def test_home_and_classic_share_native_unrestricted_momentum(self):
        carousel = (ROOT / 'SourceReadSwift/Features/Bookshelf/HomeBookCarousel.swift').read_text(encoding='utf8')
        self.assertIn('.viewAligned(limitBehavior: .never)', carousel)
        self.assertNotIn('.scrollTargetBehavior(.paging)', carousel)
        self.assertIn('phase == .idle', carousel)
        self.assertIn('if #unavailable(iOS 18) { selection = id }', carousel)
        desk = (ROOT / 'SourceReadSwift/Features/Bookshelf/ReadingDeskPager.swift').read_text(encoding='utf8')
        self.assertIn('HomeBookCarousel(', desk)
        self.assertNotIn('.scrollTargetBehavior(.paging)', desk)

    def test_browsing_uses_native_tab_minimization_without_custom_scroll_chrome(self):
        root = (ROOT / 'SourceReadSwift/App/RootTabView.swift').read_text(encoding='utf8')
        self.assertIn('.tabBarMinimizeBehavior(.onScrollDown)', root)
        self.assertIn("isHidden ? .hidden : .automatic", root)
        self.assertNotIn('lastNonSearchTab', root)
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        self.assertNotIn('.collapsingNavigationBarModern(', shelf)
        self.assertNotIn('.scrollCollapsedNavigationBar(', shelf)
        discover = (ROOT / 'SourceReadSwift/Features/Discover/DiscoverView.swift').read_text(encoding='utf8')
        self.assertIn('@StateObject var viewModel: DiscoverViewModel', discover)
        self.assertIn('self._viewModel = StateObject(wrappedValue:', discover)

    def test_cover_backdrop_belongs_to_page_not_a_rectangular_section(self):
        shelf = (ROOT / 'SourceReadSwift/Features/Bookshelf/BookshelfView.swift').read_text(encoding='utf8')
        backdrop = shelf.split('private var bookshelfBackdrop:', 1)[1].split('private var readingSection:', 1)[0]
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
