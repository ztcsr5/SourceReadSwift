"""Startup/refresh source contracts; these do not measure device frame times."""
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class StartupMotionScopeTests(unittest.TestCase):
    def test_cold_launch_does_not_wait_for_an_appearance_callback_to_show_home(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/Navigation/ReaderNavigationHost.swift").read_text(encoding="utf8")
        reveal = source.split('func stageLaunchReveal(for home:', 1)[1].split('override func viewDidLayoutSubviews', 1)[0]
        self.assertNotIn("home.alpha = 0", reveal)
        self.assertIn("home.alpha = 1", reveal)

    def test_writing_service_does_not_enumerate_interfaces_or_create_engine_at_launch(self):
        source = (ROOT / "SourceReadSwift/App/AppState.swift").read_text(encoding="utf8")
        initializer = source.split("    init(", 1)[1].split("    func record(", 1)[0]
        self.assertIn("private(set) lazy var sourceWritingServer: LightweightHTTPServer", source)
        self.assertNotIn("self.sourceWritingServer =", initializer)
        self.assertNotIn("self.sourceWritingServer.bind", initializer)

    def test_low_frequency_stores_restore_only_on_first_use(self):
        source = (ROOT / "SourceReadSwift/App/AppState.swift").read_text(encoding="utf8")
        initializer = source.split("    init(", 1)[1].split("    func record(", 1)[0]
        forwarding = source.split("private func bindChildStores()", 1)[1].split("func makeAppDataBackupSnapshot", 1)[0]
        for name in ("rssArticleStateStore", "rssFeedCacheStore", "rssArticleContentCacheStore", "sourceDiagnosticHistoryStore"):
            with self.subTest(store=name):
                self.assertIn(f"private(set) lazy var {name}:", source)
                self.assertNotIn(f"self.{name} = {name} ??", initializer)
                self.assertNotIn(f"{name}.objectWillChange", forwarding)
        for name in ("sourceStore", "bookshelfStore"):
            self.assertIn(f"self.{name} =", initializer)
        for name in ("chapterContentCacheStore", "sourceCookieStore"):
            self.assertIn(f"private(set) lazy var {name}:", source)
            self.assertNotIn(f"self.{name} =", initializer)

    def test_normal_root_uses_adaptive_refresh_and_legacy_probe_is_bounded(self):
        source = (ROOT / "SourceReadSwift/Shared/Performance/FrameRateCoordinator.swift").read_text(encoding="utf8")
        self.assertIn("private var legacyRefreshEnabled = true", source)
        self.assertIn("if legacyRefreshEnabled", source)
        keeper = (ROOT / "SourceReadSwift/App/AppRefreshRateKeeper.swift").read_text(encoding="utf8")
        self.assertIn("maximumDiagnosticDuration: TimeInterval = 30", keeper)
        self.assertIn("willResignActiveNotification", keeper)
        self.assertIn("deadline?.cancel()", keeper)
        self.assertIn("guard isEnabled, window != nil", keeper)
        self.assertIn("diagnosticDefaultsKey", keeper)
        settings = (ROOT / "SourceReadSwift/Features/Settings/ReaderPerformanceDiagnosticsView.swift").read_text(encoding="utf8")
        self.assertIn("AppRefreshRateKeeper.diagnosticDefaultsKey", settings)
        self.assertIn("30 秒", settings)


if __name__ == "__main__":
    unittest.main()
