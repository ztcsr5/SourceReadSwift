"""Verify repository-scoped CI authentication without network or real credentials.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_ci_repository_auth.py -q
"""
import contextlib
import io
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


AUTH_DIRECTORY = Path(__file__).resolve().parents[1] / "docs/reader-recovery-119"
sys.path.insert(0, str(AUTH_DIRECTORY))
from ci_repository_auth import resolve_repository_auth


class CIRepositoryAuthTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ci-auth-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.environment = dict(os.environ)
        for name in ["GH_TOKEN", "GITHUB_TOKEN", "READER_CI_REMOTE"]:
            self.environment.pop(name, None)
        self.git("init", "-q")
        self.git("remote", "add", "origin", "https://github.com/new-owner/reader.git")
        self.git("remote", "add", "primary-archive", "https://github.com/old-owner/reader.git")
        self.git("config", "credential.helper", "")
        self.helper_trace = self.root / "credential-query.txt"
        helper = self.root / "credential-fixture.py"
        helper.write_text(
            "import os, pathlib, sys\n"
            "if sys.argv[-1] != 'get': raise SystemExit(0)\n"
            "request = dict(line.rstrip('\\n').split('=', 1) for line in sys.stdin if '=' in line)\n"
            f"pathlib.Path({str(self.helper_trace)!r}).write_text(repr(request) + '\\n' + repr({{name: os.environ.get(name) for name in ['GIT_TERMINAL_PROMPT', 'GCM_INTERACTIVE']}}), encoding='utf8')\n"
            "tokens = {'new-owner/reader.git': 'fixture-new-token', 'old-owner/reader.git': 'fixture-old-token', 'new-owner/reader': 'fixture-no-suffix-token'}\n"
            "token = tokens.get(request.get('path'))\n"
            "if token: print('username=fixture\\npassword=' + token)\n",
            encoding="utf8",
        )
        command = "!" + shlex.quote(sys.executable.replace("\\", "/")) + " " + shlex.quote(str(helper).replace("\\", "/"))
        self.git("config", "--add", "credential.helper", command)

    def git(self, *arguments):
        result = subprocess.run(["git", *arguments], cwd=self.root, env=self.environment,
                                text=True, encoding="utf8", capture_output=True, check=True)
        return result.stdout

    def test_credentials_follow_the_selected_repository_path(self):
        repository, authorization = resolve_repository_auth(self.root, self.environment)
        self.assertEqual(repository, "new-owner/reader")
        self.assertEqual(authorization, "Bearer fixture-new-token")
        self.assertIn("'path': 'new-owner/reader.git'", self.helper_trace.read_text(encoding="utf8"))
        self.environment["READER_CI_REMOTE"] = "primary-archive"
        repository, authorization = resolve_repository_auth(self.root, self.environment)
        self.assertEqual(repository, "old-owner/reader")
        self.assertEqual(authorization, "Bearer fixture-old-token")
        self.assertIn("'path': 'old-owner/reader.git'", self.helper_trace.read_text(encoding="utf8"))

    def test_credentials_keep_the_actual_remote_path_when_git_suffix_is_omitted(self):
        self.git("remote", "set-url", "origin", "https://github.com/new-owner/reader")
        self.assertEqual(resolve_repository_auth(self.root, self.environment),
                         ("new-owner/reader", "Bearer fixture-no-suffix-token"))
        self.assertIn("'path': 'new-owner/reader'", self.helper_trace.read_text(encoding="utf8"))

    def test_environment_token_precedes_credentials_and_url_compatibility(self):
        self.git("remote", "set-url", "origin", "https://fixture-user:fixture-url-token@github.com/new-owner/reader.git")
        self.environment.update(GH_TOKEN="fixture-gh-token", GITHUB_TOKEN="fixture-github-token")
        self.assertEqual(resolve_repository_auth(self.root, self.environment),
                         ("new-owner/reader", "Bearer fixture-gh-token"))
        self.assertFalse(self.helper_trace.exists())
        del self.environment["GH_TOKEN"]
        self.assertEqual(resolve_repository_auth(self.root, self.environment)[1], "Bearer fixture-github-token")

    def test_embedded_legacy_auth_remains_readable_without_mutating_the_remote(self):
        remote = "https://fixture-user:fixture-url-token@github.com/old-owner/reader.git"
        self.git("remote", "set-url", "origin", remote)
        repository, authorization = resolve_repository_auth(self.root, self.environment)
        self.assertEqual(repository, "old-owner/reader")
        self.assertEqual(authorization, "Basic Zml4dHVyZS11c2VyOmZpeHR1cmUtdXJsLXRva2Vu")
        self.assertEqual(self.git("remote", "get-url", "origin").strip(), remote)
        self.assertFalse(self.helper_trace.exists())

    def test_missing_credentials_fail_noninteractively_without_outputting_secrets(self):
        self.git("remote", "set-url", "origin", "https://github.com/unconfigured/reader.git")
        output = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            with self.assertRaisesRegex(RuntimeError, "No GitHub credential") as raised:
                resolve_repository_auth(self.root, self.environment)
        self.assertEqual(output.getvalue(), "")
        self.assertNotIn("fixture-", str(raised.exception))
        self.assertNotIn("password", str(raised.exception).lower())
        trace = self.helper_trace.read_text(encoding="utf8")
        self.assertIn("'GIT_TERMINAL_PROMPT': '0'", trace)
        self.assertIn("'GCM_INTERACTIVE': 'Never'", trace)

    def test_rejects_non_github_remote_before_resolving_credentials(self):
        self.git("remote", "set-url", "origin", "https://fixture-user:fixture-url-token@example.invalid/new-owner/reader.git")
        with self.assertRaisesRegex(ValueError, "HTTPS github.com") as raised:
            resolve_repository_auth(self.root, self.environment)
        self.assertNotIn("fixture-url-token", str(raised.exception))
        self.assertFalse(self.helper_trace.exists())

    def test_invalid_remote_selection_cannot_become_a_git_option(self):
        self.environment["READER_CI_REMOTE"] = "--all"
        with self.assertRaisesRegex(ValueError, "remote name"):
            resolve_repository_auth(self.root, self.environment)
        self.assertFalse(self.helper_trace.exists())


if __name__ == "__main__":
    unittest.main()
