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
        self.assertIn("enabled: ReaderExitSwipePolicy.isProseFallbackEnabled(", bridge)
        self.assertIn("allowsBookReturn: allowsNativeBookReturn", bridge)
    def test_reduced_motion_cannot_pass_when_both_input_probes_are_zero(self):
        source = (ROOT / "SourceReadSwiftUITests/FloatingReadingDeskUITests.swift").read_text(encoding="utf8")
        self.assertIn("motionAfter + fallbackAfter, motionBefore + fallbackBefore", source)
        self.assertIn("XCTAssertGreaterThan(motionAfter, motionBefore", source)
        bridge = (ROOT / "SourceReadSwift/Features/Reader/ReaderExitSwipeBridge.swift").read_text(encoding="utf8")
        self.assertIn("gesture.numberOfTouches > 0", bridge)
        self.assertIn("edgePan.require(toFail: nativeEdge)", bridge)
