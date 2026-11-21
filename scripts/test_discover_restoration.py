"""Guard the requested pre-redesign Discover UI and retained functional fixes.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_discover_restoration.py
These are source contracts, not simulator or touch-interaction tests.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DiscoverRestorationTests(unittest.TestCase):
    def setUp(self):
        self.source = (ROOT / "SourceReadSwift/Features/Discover/DiscoverView.swift").read_text(encoding="utf8")

    def test_root_routes_category_browsing_and_online_search_separately(self):
        root = (ROOT / "SourceReadSwift/App/RootTabView.swift").read_text(encoding="utf8")
        search = (ROOT / "SourceReadSwift/Features/Search/GlobalSearchView.swift").read_text(encoding="utf8")
        self.assertEqual(root.count('DiscoverView(mode: .explore)'), 2)
        self.assertEqual(root.count('viewModel: appState.discoverViewModel'), 2)
        self.assertIn('mode: .search', search)
        for removed in ('GlobalSearchIndex', '快捷入口', '搜索应用功能'):
            self.assertNotIn(removed, search)
        self.assertNotIn('Button("全网搜索"', self.source)
        self.assertNotIn('Button("分类寻书"', self.source)

    def test_original_controls_replace_rejected_editorial_page(self):
        for control in ('.searchable(text: $viewModel.keyword', "bookSearchTab", "bookExploreTab",
                        "mediumFilterPillBar", "searchResultScopeBar",
                        '.accessibilityIdentifier("discover.matchMode")'):
            self.assertIn(control, self.source)
        for rejected in ('DiscoverEditorialHeading', 'DiscoverSectionTabs', '"试试搜"', '"找一本想读的书"',
                         'useSearchCardFill'):
            self.assertNotIn(rejected, self.source)

    def test_search_layout_keeps_matching_and_scope_controls_together(self):
        header = self.source.split('private var bookSearchTab:', 1)[1].split('private var content:', 1)[0]
        self.assertRegex(header, r'matchModePicker\s+searchResultScopeBar')
        picker = self.source.split('private var matchModePicker:', 1)[1].split('///', 1)[0]
        self.assertIn('.frame(width: 156, height: 44)', picker)
        self.assertRegex(picker, r'HStack \{\s+Spacer\(minLength: 0\)\s+Picker')
        self.assertIn('viewModel.hasSearchState', header)
        self.assertIn('viewModel.selectedSourceURL != nil', header)
        self.assertIn('.accessibilityIdentifier("discover.resultScopeBar")', header)

    def test_notice_lifetime_and_membership_snapshot_are_preserved(self):
        self.assertIn("shelfNoticeTask?.cancel()", self.source)
        self.assertIn("2_500_000_000", self.source)
        self.assertIn("shelfMembershipDirty", self.source)
        self.assertIn("cachedShelfMembership", self.source)
        self.assertIn('.accessibilityElement(children: .ignore)', self.source)
        self.assertIn('.accessibilityIdentifier("discover.shelfAddNotice")', self.source)

    def test_visual_restore_does_not_restore_direct_haptics(self):
        self.assertNotIn("UIImpactFeedbackGenerator", self.source)


if __name__ == "__main__":
    unittest.main()
