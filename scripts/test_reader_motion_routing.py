"""Source contracts for routing; native geometry/animation tests run on iOS."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReaderMotionRoutingTests(unittest.TestCase):
    def test_curl_and_slide_use_native_page_view_controller_host(self):
        reader = (ROOT / "SourceReadSwift/Features/Reader/ReaderView.swift").read_text(encoding="utf8")
        content = reader.split("private var readerContent:", 1)[1].split("private var scrollModeParagraphs:", 1)[0]
        self.assertIn(".pageCurl", content)
        self.assertIn("pagedReaderContent", content)
        pager = reader.split("private var pagedReaderContent:", 1)[1].split("private func commitCoverTurn", 1)[0]
        self.assertIn("nativePagedReaderContent", pager)
        self.assertIn("PageCurlReaderView(", pager)
        self.assertIn("coverPagedReaderContent", pager)
        self.assertIn("turnRequest: tapPageTurnRequest", pager)
        self.assertNotIn("pagedPageIndex = pagedPageIndex +", pager)

    def test_all_paged_modes_are_mapped_by_position_and_automation(self):
        for relative in ["ReaderPositionMapping.swift", "ReaderAutomationPolicy.swift"]:
            source = (ROOT / "SourceReadSwift/Features/Reader" / relative).read_text(encoding="utf8")
            for mode in ["verticalSlide", "parallax", "wipe", "split", "perspective"]:
                self.assertIn("." + mode, source, relative)

    def test_curl_does_not_allocate_a_display_link(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/ReaderCurlSurface.swift").read_text(encoding="utf8")
        self.assertNotIn("CADisplayLink", source)
        self.assertIn("contentsRect", source)

    def test_curl_rewarms_after_viewport_resize_invalidates_capture(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/CoverPageReaderView.swift").read_text(encoding="utf8")
        resize = source.split("if lastSize != size {", 1)[1].split("let minY =", 1)[0]
        self.assertIn("curl?.invalidate()", resize)
        self.assertIn("scheduleWarmup()", resize)

    def test_tap_handoff_is_claimed_after_the_host_validates_its_target(self):
        reader_root = ROOT / "SourceReadSwift/Features/Reader"
        reader = (reader_root / "ReaderView.swift").read_text(encoding="utf8")
        request = reader.split("private func requestAnimatedPageTurn", 1)[1].split("private func requestPageStep", 1)[0]
        self.assertNotIn("DispatchQueue", request)
        self.assertIn("pageIdentity: ReaderPageIdentity", request)
        host = (reader_root / "CoverPageReaderView.swift").read_text(encoding="utf8")
        turn = host.split("func requestTurn(", 1)[1].split("func beginInteraction(", 1)[0]
        self.assertIn("queuedTurnRequest = request", turn.split("DispatchQueue", 1)[0])
        self.assertIn("request.claim(pageIdentity: identity, style: style)", turn.split("request.direction > 0 ? window.hasNext", 1)[1])
        self.assertNotIn("warmCurrentCurlPage()", turn, "A tap must not rasterize a full page synchronously")
        self.assertIn("private static let requestedCurlTurnDuration: TimeInterval = 0.42", host)
        self.assertIn("Self.requestedCurlTurnDuration", turn)
        warmup = host.split("private func scheduleWarmup()", 1)[1].split("private func canWarmPages", 1)[0]
        self.assertIn("self.warmCurrentCurlPage()", warmup)
        self.assertIn("self.warmNextCurlPage()", warmup)

    def test_visible_page_identity_waits_for_the_installed_uikit_snapshot(self):
        reader = (ROOT / "SourceReadSwift/Features/Reader/ReaderView.swift").read_text(encoding="utf8")
        host = (ROOT / "SourceReadSwift/Features/Reader/CoverPageReaderView.swift").read_text(encoding="utf8")
        cover = reader.split("private var customPagedReaderContent:", 1)[1].split("/// Commit one cover-mode turn.", 1)[0]
        commit = reader.split("private func commitCoverTurn", 1)[1].split("private func recordVisiblePageIdentity", 1)[0]
        self.assertIn("onPageInstalled: { identity in", cover)
        self.assertIn("self.onPageInstalled?(identity)", host)
        self.assertNotIn("reportCoverVisibleIdentity", commit)


if __name__ == "__main__":
    unittest.main()
