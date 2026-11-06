"""Guard the requested reader fallback without weakening native-return assertions.
Usage: python -m unittest discover -s scripts -p test_reader_fallback_boundary.py
"""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ReaderFallbackBoundaryTests(unittest.TestCase):
    def test_enabled_native_flag_does_not_disable_the_fallback(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/ReaderExitSwipeBridge.swift").read_text(encoding="utf8")
        self.assertIn("let needsFallback = exitEnabled\n", source)
    def test_prose_call_site_can_enable_a_fallback_without_the_menu(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/ReaderView.swift").read_text(encoding="utf8")
        bridge = source.split(".background(ReaderExitSwipeBridge(", 1)[1].split("))", 1)[0]
        self.assertIn("enabled: allowsNativeBookReturn ||", bridge)
