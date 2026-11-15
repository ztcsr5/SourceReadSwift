"""Guard the source queue and library refresh entry points.

Run with: python -B -X utf8 -m unittest discover -s scripts -p test_source_library_paths.py
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1] / "SourceReadSwift"


class SourceLibraryPathTests(unittest.TestCase):
    def test_discover_drains_the_queue_but_keeps_per_source_timeout_and_cancellation(self):
        discover = (ROOT / "Features/Discover/DiscoverView.swift").read_text(encoding="utf8")
        search = discover.split("    func search(generation:", 1)[1].split("    private func filtered", 1)[0]
        self.assertNotIn("overallDeadline", search)
        self.assertIn("if let next = iterator.next()", search)
        self.assertIn("AsyncTimeout.run(seconds: 10)", search)
        self.assertIn("group.cancelAll()", search)

    def test_launch_and_pull_refresh_use_the_same_shelf_queue(self):
        app = (ROOT / "App/SourceReadSwiftApp.swift").read_text(encoding="utf8")
        shelf = (ROOT / "Features/Bookshelf/BookshelfView.swift").read_text(encoding="utf8")
        self.assertIn("bookshelfChapterRefresh.refreshOnLaunch()", app)
        self.assertIn("bookshelfChapterRefresh.refresh()", shelf)

    def test_shelf_uses_a_red_update_indicator(self):
        shelf = (ROOT / "Features/Bookshelf/BookshelfView.swift").read_text(encoding="utf8")
        self.assertGreaterEqual(shelf.count("ShelfUpdateIndicator()"), 3)
        self.assertIn("Color(uiColor: .systemRed)", shelf)


if __name__ == "__main__":
    unittest.main()
