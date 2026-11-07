"""Guard production source transport boundaries; run with unittest discovery.
Native URLProtocol regressions verify behavior without external hosts.
"""
from pathlib import Path
import unittest
import re
ROOT = Path(__file__).resolve().parents[1]
class SourceTransportBoundaryTests(unittest.TestCase):
    def test_transport_does_not_trust_all_certificates_or_downgrade_tls(self):
        source = (ROOT / "SourceReadSwift/Core/Network/SourceRequest.swift").read_text(encoding="utf8")
        self.assertNotIn("URLCredential(trust:", source)
        self.assertNotIn('replacingOccurrences(of: "https://", with: "http://"', source)
    def test_both_redirect_paths_share_the_origin_policy(self):
        source = (ROOT / "SourceReadSwift/Core/Network/SourceRequest.swift").read_text(encoding="utf8")
        self.assertEqual(source.count("SourceRedirectPolicy.redirect("), 2)
        self.assertIn('urlRequest.value(forHTTPHeaderField: "Cookie") == nil', source)
    def test_secure_cookies_check_the_request_scheme(self):
        source = (ROOT / "SourceReadSwift/Core/Storage/SourceCookieStore.swift").read_text(encoding="utf8")
        self.assertIn('!cookie.isSecure || isHTTPS', source)
    def test_huahuo_reuses_canonical_extension_decoding(self):
        source = (ROOT / "SourceReadSwift/Core/Import/HuaHuoBookSourceAdapter.swift").read_text(encoding="utf8")
        self.assertIn('metadata = try BookSource(from: decoder)', source)
        self.assertIn('bookSourceType: raw.metadata.bookSourceType', source)
        self.assertIn('loginCheckJs: raw.metadata.loginCheckJs', source)
    def test_redirect_repair_does_not_scan_query_parameters_for_another_url(self):
        source = (ROOT / "SourceReadSwift/Core/Network/SourceRequest.swift").read_text(encoding="utf8")
        self.assertFalse('let searchStart = trimmed.index' in source, "Double-origin repair must be anchored before path/query")
    def test_production_double_origin_regex_preserves_nested_urls(self):
        source = (ROOT / "SourceReadSwift/Core/Network/SourceRequest.swift").read_text(encoding="utf8")
        section = source.split("// Repair only a second scheme", 1)[1].split("// Handle protocol-relative", 1)[0]
        pattern = re.search(r'pattern: #"(.*?)"#', section).group(1)
        for url in ["https://fixture.invalid/login?next=https://other.invalid/read",
                    "https://fixture.invalid/proxy/https://other.invalid/read"]:
            self.assertIsNone(re.match(pattern, url), url)
        for prefix in ["http://fixture.invalid", "https://fixture.invalid"]:
            self.assertEqual(re.match(pattern, prefix + "https://other.invalid/read").group(1),
                             "https://other.invalid/read")
    def test_html_redirect_limit_cannot_return_a_guard_page_as_a_chapter(self):
        source = (ROOT / "SourceReadSwift/Core/Network/SourceRequest.swift").read_text(encoding="utf8")
        self.assertFalse('if redirectCount <= maxRedirects {' in source,
                         "HTML redirect overflow must return failure, not fall through to success")
    def test_comic_non_eof_safety_is_exercised_over_real_loopback_http(self):
        tests = (ROOT / "SourceReadSwiftTests/RemoteComicImageTests.swift").read_text(encoding="utf8")
        case = tests.split('func testOversizedComicResponsesStopBeforeTheServerFinishes', 1)[1].split('    func ', 1)[0]
        self.assertTrue('HeldComicHTTPServer' in case, "Use a real held-open socket for the non-EOF requirement")
        self.assertTrue('timeout: 4' in case)
    def test_global_search_selection_explicitly_releases_keyboard_focus(self):
        source = (ROOT / "SourceReadSwift/Features/Search/GlobalSearchView.swift").read_text(encoding="utf8")
        link = source.split('private func resultLink', 1)[1].split('@ViewBuilder', 1)[0]
        self.assertTrue('isFocused = false' in link)
        self.assertTrue('selectedEntry = entry' in link)
