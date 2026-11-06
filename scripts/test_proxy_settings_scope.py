"""Guard the proxy form commit boundary. Run with unittest discovery from scripts."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ProxySettingsScopeTests(unittest.TestCase):
    def test_form_edits_do_not_bind_live_network_configuration(self):
        screen = (ROOT / "SourceReadSwift/Features/Settings/SourceProxySettingsView.swift").read_text(encoding="utf8")
        self.assertNotIn("$proxyManager.", screen)
        self.assertIn("try proxyManager.save(", screen)

    def test_leaving_settings_cancels_the_probe(self):
        screen = (ROOT / "SourceReadSwift/Features/Settings/SourceProxySettingsView.swift").read_text(encoding="utf8")
        self.assertIn(".onDisappear", screen)
        self.assertIn("testTask?.cancel()", screen)
