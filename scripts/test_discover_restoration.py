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

    def test_original_controls_replace_rejected_editorial_page(self):
        for control in ('BrandSegmentedControl("寻书方式"', 'case search = "全网搜索"',
                        'case explore = "分类寻书"', "mediumFilterPillBar", "searchResultScopeBar",
                        '.accessibilityIdentifier("discover.matchMode")'):
            self.assertIn(control, self.source)
        for rejected in ('DiscoverEditorialHeading', 'DiscoverSectionTabs', '"试试搜"'):
            self.assertNotIn(rejected, self.source)

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
