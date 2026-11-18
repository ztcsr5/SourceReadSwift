"""Source contracts for cancellation boundaries; native behavior lives in XCTest."""
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
READER = ROOT / "SourceReadSwift/Features/Reader"


class ReaderPaginationCancellationContracts(unittest.TestCase):
    def test_detached_worker_receives_parent_cancellation(self):
        source = (READER / "ReaderAsyncPaginationCoordinator.swift").read_text(encoding="utf8")
        self.assertTrue("withTaskCancellationHandler" in source, "Parent must own worker cancellation")
        self.assertTrue("worker.cancel()" in source, "Cancelled parent must cancel its detached worker")

    def test_each_layout_loop_checks_cancellation(self):
        text = (READER / "ReaderTextPagePaginator.swift").read_text(encoding="utf8")
        illustrated = (READER / "ReaderChapterPaginator.swift").read_text(encoding="utf8")
        self.assertTrue("while characterEnd < document.length {\n            guard !Task.isCancelled" in text)
        self.assertTrue("for (index, paragraph) in paragraphs.enumerated() {\n            guard !Task.isCancelled" in illustrated)

    def test_text_warmup_is_nearest_first_and_stale_work_is_stopped(self):
        source = (READER / "ReaderView.swift").read_text(encoding="utf8")
        self.assertTrue(".onDisappear { pageTextCache.cancelPrewarm() }" in source)
        self.assertTrue("cache.isCurrentPrewarm(generation, signature: signature)" in source)
        self.assertTrue("abs($0 - index) < abs($1 - index)" in source)


if __name__ == "__main__":
    unittest.main()
