"""Contracts and regression tests for SourceRead 1.1.8 (Build 138).

Usage:
    python -B -X utf8 -m unittest discover -s scripts -p test_release118_quality.py
"""
import os
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "SourceReadSwift"


def read_text(relative_path: str) -> str:
    path = ROOT / relative_path
    return path.read_text(encoding="utf8")


class Release118QualityTests(unittest.TestCase):
    def test_version_bump_across_project_and_workflows(self):
        project = read_text("project.yml")
        self.assertIn('MARKETING_VERSION: "1.1.8"', project)
        self.assertIn('CURRENT_PROJECT_VERSION: "138"', project)

        for workflow in ["unsigned-ipa.yml", "ios.yml", "floating-desk.yml"]:
            content = read_text(f".github/workflows/{workflow}")
            self.assertIn("SourceRead 1.1.8 · Build 138", content)

    def test_brand_header_has_no_version_and_about_view_has_unified_mark(self):
        header = read_text("SourceReadSwift/Features/Settings/SettingsBrandHeader.swift")
        self.assertNotIn("identity.version", header)
        self.assertNotIn('version: "', header)

        settings = read_text("SourceReadSwift/Features/Settings/SettingsView.swift")
        self.assertIn("PaperBetweenMark(size: 56)", settings)
        self.assertIn("PaperBetweenMark", settings)

        theme = read_text("SourceReadSwift/Shared/DesignSystem/AppVisualTheme.swift")
        self.assertIn("struct PaperBetweenMark: View", theme)

    def test_app_icon_asset_exists_and_matches_specs(self):
        icon_path = APP / "App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
        self.assertTrue(icon_path.exists())
        self.assertGreater(icon_path.stat().st_size, 10000)

    def test_search_moved_to_tab_bar_and_removed_from_shelf_top_bar(self):
        shelf = read_text("SourceReadSwift/Features/Bookshelf/BookshelfView.swift")
        # Magnifying glass button must not be in the top toolbar
        self.assertNotIn('Button { showsSearch = true } label: { Image(systemName: "magnifyingglass")', shelf)
        self.assertIn('"bookshelf.globalSearch"', shelf)

        tab_bar = read_text("SourceReadSwift/Shared/DesignSystem/LegacyTabBar.swift")
        self.assertIn('"bookshelf.globalSearch"', tab_bar)

        root = read_text("SourceReadSwift/App/RootTabView.swift")
        self.assertIn("showsGlobalSearch = true", root)

    def test_precache_window_radius_and_disk_caching(self):
        reader = read_text("SourceReadSwift/Features/Reader/ReaderView.swift")
        self.assertIn("max(base, 5)", reader)
        self.assertIn("precacheDiskWindow(around", reader)
        self.assertIn("appState.chapterContentCacheStore", reader)
        self.assertIn("chapters[index].index == index", reader)

    def test_chapter_large_jump_memory_pruning(self):
        reader = read_text("SourceReadSwift/Features/Reader/ReaderView.swift")
        self.assertIn("windowSections.removeAll { abs($0.chapterIndex - index) > windowRadius }", reader)
        self.assertIn("windowSections.removeAll { abs($0.chapterIndex - section.chapterIndex) > windowRadius }", reader)

    def test_reader_120hz_promotion_optimization(self):
        cover = read_text("SourceReadSwift/Features/Reader/CoverPageReaderView.swift")
        self.assertIn("page?.layer.shadowPath = UIBezierPath(rect: bounds).cgPath", cover)
        self.assertIn("pan.delaysTouchesBegan = false", cover)
        self.assertIn("pan.delaysTouchesEnded = false", cover)

    def test_reader_opening_page_literary_quotes_and_mark(self):
        opening = read_text("SourceReadSwift/Features/Bookshelf/ReaderOpeningPage.swift")
        self.assertIn("PaperBetweenMark(size: 48)", opening)
        self.assertIn("literaryQuotes", opening)
        self.assertIn("reader.openingProgress", opening)
        self.assertIn("正在打开正文", opening)

    def test_title_page_completely_removed(self):
        detail = read_text("SourceReadSwift/Features/Discover/BookDetailView.swift")
        self.assertNotIn("查看书籍扉页", detail)
        self.assertNotIn("TitlePageView", detail)

    def test_book_detail_intro_expansion_and_sanitization(self):
        summary = read_text("SourceReadSwift/Features/Discover/BookDetailSummary.swift")
        self.assertIn("sanitizeIntro", summary)
        self.assertIn("expanded", summary)
        self.assertIn("lineLimit(intro.count > 90 && !expanded ? 4 : nil)", summary)

    def test_ai_assistant_web_integration(self):
        ai = read_text("SourceReadSwift/Features/Settings/AIChatView.swift")
        self.assertIn("enum AIAssistantMode", ai)
        self.assertIn("doubao", ai)
        self.assertIn("kimi", ai)
        self.assertIn("deepseek", ai)
        self.assertIn("AIWebAssistantView", ai)
        self.assertIn("AIWebViewContainer", ai)
        self.assertIn("websiteDataStore = .default()", ai)
        self.assertIn("webToolbar", ai)

    def test_purify_rules_presets_expanded_and_valid(self):
        store = read_text("SourceReadSwift/Core/Storage/PurifyRuleStore.swift")
        for preset_id in ["anti-scraping", "social-groups", "author-notes", "transcode-alerts"]:
            self.assertIn(f'id: "{preset_id}"', store)

        # Extract and compile all patterns
        pattern_matches = re.findall(r'"([^"\n]+##)"', store)
        self.assertGreater(len(pattern_matches), 10)
        for pattern_rule in pattern_matches:
            raw_regex = pattern_rule.split("##")[0]
            try:
                re.compile(raw_regex)
            except re.error as e:
                self.fail(f"Invalid regex in PurifyRulePreset: {raw_regex} ({e})")

    def test_rule_validator_chained_js_support(self):
        validator = read_text("SourceReadSwift/Core/Rules/RuleEditorValidator.swift")
        self.assertIn('trimmed.range(of: "<js>")', validator)
        self.assertIn('trimmed.range(of: "</js>"', validator)


if __name__ == "__main__":
    unittest.main()
