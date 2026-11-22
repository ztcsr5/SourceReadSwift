"""Source contracts for the November 22 reader follow-up; not device tests."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1] / "SourceReadSwift"


class ReaderFeedbackFollowupTests(unittest.TestCase):
    def test_refresh_targets_the_live_reader_instead_of_reloading_the_opening_chapter(self):
        reader = (ROOT / "Features/Reader/ReaderView.swift").read_text(encoding="utf8")
        self.assertNotIn("var onRefreshChapter:", reader)
        refresh = reader.split("private func refreshDisplayedChapter()", 1)[1].split("\n    private ", 1)[0]
        self.assertIn("refreshableChapterIndex", refresh)
        self.assertIn("ignoresCache: true", refresh)
        self.assertIn("upsertWindowSection", refresh)
        self.assertNotIn("resetWindow()", refresh)
        self.assertNotIn("onSelectChapter", refresh)

    def test_history_is_independent_of_shelf_membership(self):
        detail = (ROOT / "Features/Discover/BookDetailView.swift").read_text(encoding="utf8")
        gateway = (ROOT / "Features/Bookshelf/BookshelfReaderGatewayView.swift").read_text(encoding="utf8")
        self.assertIn("appState.recordUnshelvedReading", detail)
        self.assertIn("onPreviewPosition: recordHistoryPosition", gateway)

    def test_directory_and_prose_use_the_same_loading_surface(self):
        detail = (ROOT / "Features/Discover/BookDetailView.swift").read_text(encoding="utf8")
        gateway = (ROOT / "Features/Bookshelf/BookshelfReaderGatewayView.swift").read_text(encoding="utf8")
        surface = (ROOT / "Features/Bookshelf/ReaderOpeningPage.swift").read_text(encoding="utf8")
        self.assertIn("ReaderChapterLoadingSurface(bookID: book.id)", gateway)
        self.assertIn("ReaderChapterLoadingSurface(bookID: bookID, chapterTitle: effectiveChapter.title)", detail)
        self.assertIn("正在准备章节目录", surface)
        self.assertIn("正在加载正文", surface)

    def test_native_curl_keeps_its_cadence_without_rasterizing_at_gesture_start(self):
        curl = (ROOT / "Features/Reader/PageCurlReaderView.swift").read_text(encoding="utf8")
        self.assertNotIn("shouldRasterize", curl)
        self.assertIn("preferredFrameRateRange = CAFrameRateRange(minimum: 120", curl)
        self.assertIn("!self.isGestureDragging", curl)


if __name__ == "__main__":
    unittest.main()
