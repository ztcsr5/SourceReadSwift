"""Keep full source diagnostics honest about failed stages and unreadable content."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SourceDebugDiagnosticsTests(unittest.TestCase):
    def test_full_search_rejects_an_empty_result(self):
        source = (ROOT / "SourceReadSwift/Features/Discover/SourceWritingView.swift").read_text(encoding="utf8")
        search = source.split("// 1. Search step", 1)[1].split("// 2. Detail step", 1)[0]
        section = search.split("if books.isEmpty {", 1)[1].split("} else {", 1)[0]
        self.assertIn('if step == "all"', section)
        self.assertIn("errorMessage =", section)

    def test_later_stage_failures_are_not_hidden_in_full_mode(self):
        source = (ROOT / "SourceReadSwift/Features/Discover/SourceWritingView.swift").read_text(encoding="utf8")
        sections = [
            source.split("// 2. Detail step", 1)[1].split("// 3. TOC step", 1)[0],
            source.split("// 3. TOC step", 1)[1].split("// 4. Content step", 1)[0],
            source.split("// 4. Content step", 1)[1].split("let totalDuration", 1)[0],
        ]
        for section in sections:
            failure = section.split("case .failure(let error):", 1)[1].split("logStep", 1)[0]
            self.assertIn("errorMessage =", failure)
            self.assertNotIn("if step ==", failure)

    def test_empty_catalog_and_non_readable_content_fail(self):
        source = (ROOT / "SourceReadSwift/Features/Discover/SourceWritingView.swift").read_text(encoding="utf8")
        self.assertIn("目录解析成功但没有章节", source)
        self.assertIn("SourceChapterNotice.isReadableContent", source)
        self.assertIn("SourceChapterNotice.updateMessage", source)

    def test_full_explore_only_probe_rejects_empty_categories_and_results(self):
        source = (ROOT / "SourceReadSwift/Features/Discover/SourceWritingView.swift").read_text(encoding="utf8")
        explore = source.split("// 0. Explore step", 1)[1].split("// 1. Search step", 1)[0]
        self.assertEqual(explore.count('step == "all" && exploreOnly'), 3)
        self.assertIn("发现页分类为空", explore)
        self.assertIn("发现页返回 0 条", explore)


if __name__ == "__main__":
    unittest.main()
