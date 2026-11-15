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
        self.assertEqual(search.count("searchBooksWithinListingBudget("), 2)
        budget = (ROOT / "Core/Engine/SourceListingBudget.swift").read_text(encoding="utf8")
        self.assertIn("let seconds = SourceListingBudget.search(for: source)", budget)
        self.assertIn("AsyncTimeout.run(seconds: seconds)", budget)
        self.assertRegex(budget, r"let plainSearch: TimeInterval = 10\b")
        self.assertIn("SourceRequestBuilder.defaultTimeout : plainSearch", budget)
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

    def test_imported_video_kind_and_single_track_directory_use_the_media_path(self):
        source = (ROOT / "Core/Models/BookSource.swift").read_text(encoding="utf8")
        directory = (ROOT / "Core/Rules/ChapterListParser.swift").read_text(encoding="utf8")
        self.assertIn("if bookSourceType == 4 { return .video }", source)
        self.assertIn('var isMusicSource: Bool', source)
        self.assertGreaterEqual(directory.count("singleMediaChapter("), 3)

    def test_aggregate_cover_keeps_its_builder_for_real_covers_and_placeholders(self):
        discover = (ROOT / "Features/Discover/DiscoverView.swift").read_text(encoding="utf8")
        self.assertRegex(discover, r"@ViewBuilder\s+private func aggregatedCover\(")


if __name__ == "__main__":
    unittest.main()
