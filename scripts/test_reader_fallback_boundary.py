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
    def test_native_reader_does_not_mount_the_legacy_fallback(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/ReaderView.swift").read_text(encoding="utf8")
        self.assertIn("if nativeSession == nil { ReaderExitSwipeBridge", source)
        router = (ROOT / "SourceReadSwift/Features/Reader/Navigation/ReaderNavigationRouter.swift").read_text(encoding="utf8")
        self.assertIn("controller.preferredTransition = .zoom", router)
        self.assertNotIn("ReaderExitSwipeBridge", router)
    def test_pushed_reader_keeps_custom_opening_but_uses_system_pop(self):
        router = (ROOT / "SourceReadSwift/Features/Reader/Navigation/ReaderNavigationRouter.swift").read_text(encoding="utf8")
        self.assertNotIn("compatibility?.attach(to: navigation.view", router)
        self.assertIn("compatibility?.attach(to: controller.view", router)
        self.assertIn("guard operation == .push, toVC === reader else { return nil }", router)
        self.assertIn("return compatibility?.animator(isOpening: true)", router)
    def test_reduced_motion_cannot_pass_when_both_input_probes_are_zero(self):
        source = (ROOT / "SourceReadSwiftUITests/FloatingReadingDeskUITests.swift").read_text(encoding="utf8")
        self.assertIn("XCTAssertEqual(sessionEvidence.value as? String, sessionBefore", source)
        self.assertIn("XCTAssertGreaterThan(motionAfter, motionBefore", source)
        bridge = (ROOT / "SourceReadSwift/Features/Reader/ReaderExitSwipeBridge.swift").read_text(encoding="utf8")
        self.assertIn("gesture.numberOfTouches > 0", bridge)
        self.assertIn("edgePan.require(toFail: nativeEdge)", bridge)
