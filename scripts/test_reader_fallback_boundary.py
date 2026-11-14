"""Guard the requested reader fallback without weakening native-return assertions.
Usage: python -m unittest discover -s scripts -p test_reader_fallback_boundary.py
"""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ReaderFallbackBoundaryTests(unittest.TestCase):
    def test_enabled_native_flag_does_not_disable_the_fallback(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/ReaderExitSwipeBridge.swift").read_text(encoding="utf8")
        self.assertIn("let needsFallback = exitEnabled\n", source)
    def test_native_reader_does_not_mount_the_legacy_fallback(self):
        reader_source = (ROOT / "SourceReadSwift/Features/Reader/ReaderView.swift").read_text(encoding="utf8")
        self.assertIn("ReaderSystemBridgesLayer(", reader_source)
        self.assertIn("nativeSession: nativeSession", reader_source)
        self.assertNotIn("ReaderExitSwipeBridge", reader_source)
        layers_source = (ROOT / "SourceReadSwift/Features/Reader/ReaderChromeLayers.swift").read_text(encoding="utf8")
        self.assertRegex(layers_source, r"if nativeSession == nil\s*\{\s*ReaderExitSwipeBridge\b")
        router = (ROOT / "SourceReadSwift/Features/Reader/Navigation/ReaderNavigationRouter.swift").read_text(encoding="utf8")
        self.assertIn("controller.preferredTransition = .zoom", router)
        self.assertNotIn("ReaderExitSwipeBridge", router)
    def test_pushed_reader_keeps_custom_opening_but_uses_system_pop(self):
        router = (ROOT / "SourceReadSwift/Features/Reader/Navigation/ReaderNavigationRouter.swift").read_text(encoding="utf8")
        self.assertNotIn("compatibility?.attach(to: navigation.view", router)
        self.assertIn("compatibility?.attach(to: controller.view", router)
        self.assertIn("if operation == .push, toVC === reader { return compatibility?.animator(isOpening: true) }", router)
        self.assertIn("if operation == .pop, fromVC === reader, isClosingStackReader { return compatibility?.animator(isOpening: false) }", router)
    def test_reduced_motion_cannot_pass_when_both_input_probes_are_zero(self):
        source = (ROOT / "SourceReadSwiftUITests/FloatingReadingDeskUITests.swift").read_text(encoding="utf8")
        self.assertIn("XCTAssertEqual(sessionEvidence.value as? String, sessionBefore", source)
        self.assertIn("XCTAssertGreaterThan(motionAfter, motionBefore", source)
        bridge = (ROOT / "SourceReadSwift/Features/Reader/ReaderExitSwipeBridge.swift").read_text(encoding="utf8")
        self.assertIn("gesture.numberOfTouches > 0", bridge)
        self.assertIn("edgePan.require(toFail: nativeEdge)", bridge)
