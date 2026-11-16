"""Test private corpus transport with synthetic fixtures only; never read user source files.

Run: python -B -X utf8 -m unittest discover -s scripts -p test_prepare_private_source_corpus.py -v
On macOS with Swift, also executes CryptoKit cross-language round trips.
"""

import base64
from contextlib import redirect_stderr, redirect_stdout
import copy
import gzip
import io
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import prepare_private_source_corpus as corpus


class PrivateSourceCorpusTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.key = bytes(range(32))  # Public fixture key; never used for private sources.
        source = {"bookSourceUrl": "https://fixture.invalid", "jsLib": "fixture_private_marker"}
        self.originals = [b"\xef\xbb\xbf  " + json.dumps([source, source], ensure_ascii=False).encode(),
                          json.dumps([source]).encode() + b"\n"]
        inventory = []
        for index, raw in enumerate(self.originals):
            path = self.root / f"original-{index}.json"
            path.write_bytes(raw)
            inventory.append({"path": str(path), "exists": True, "bytes": len(raw),
                              "sha256": corpus.sha256(raw), "json_type": "list", "count": 2 if index == 0 else 1})
        inventory.insert(0, {"path": str(self.root / "reference.md"), "exists": True, "bytes": 1})
        self.inventory = self.root / "inventory.json"
        self.inventory.write_bytes(corpus.encode_json(inventory))
        self.bundle, self.manifest = corpus.build_bundle(self.inventory, 2, 3)

    def report(self):
        rows = [{"fileId": entry["fileId"], "fileSHA": entry["sha256"], "index": index,
                 "status": "notRun", "stages": []}
                for entry in self.manifest["files"] for index in range(entry["expectedCount"])]
        return {"schemaVersion": 1, "mode": "inspect", "generatedAt": "2026-01-01T00:00:00Z",
                "totalRecords": 3, "selectedRecords": 0, "rows": rows}

    def test_exact_original_bytes_and_duplicate_occurrences_survive_round_trip(self):
        encrypted = corpus.seal(self.bundle, self.key, "corpus", 2, 3)
        restored = corpus.unseal(encrypted, self.key, "corpus", 2, 3)
        destination = self.root / "unpacked"
        corpus.extract_bundle(restored, destination, 2, 3)
        for entry, original in zip(self.manifest["files"], self.originals):
            self.assertEqual((destination / entry["relativePath"]).read_bytes(), original)
        self.assertEqual([entry["expectedCount"] for entry in self.manifest["files"]], [2, 1])
        self.assertNotIn(b"fixture_private_marker", encrypted)
        self.assertNotIn(b"fixture_private_marker", corpus.encode_json(self.manifest))
        self.assertNotIn(str(self.root).encode(), corpus.encode_json(self.manifest))

    def test_changed_original_size_hash_and_count_fail_before_packaging(self):
        inventory = json.loads(self.inventory.read_bytes())
        for field, value in [("bytes", 1), ("sha256", "0" * 64), ("count", 1)]:
            changed = copy.deepcopy(inventory)
            changed[1][field] = value
            self.inventory.write_bytes(corpus.encode_json(changed))
            with self.subTest(field=field), self.assertRaises(ValueError):
                corpus.build_bundle(self.inventory, 2, 3)

    def test_wrong_file_or_record_count_is_rejected(self):
        for files, records in [(1, 3), (2, 2), (3, 3)]:
            with self.subTest(files=files, records=records), self.assertRaises(ValueError):
                corpus.build_bundle(self.inventory, files, records)

    def test_source_payload_changes_and_path_traversal_do_not_create_outputs(self):
        original = json.loads(self.bundle)
        for change in ["path", "sha", "raw", "order"]:
            altered = copy.deepcopy(original)
            if change == "path": altered["manifest"]["files"][0]["relativePath"] = "../outside.json"
            if change == "sha": altered["manifest"]["files"][0]["sha256"] = "f" * 64
            if change == "raw": altered["files"][0]["contentBase64"] = base64.b64encode(b"[{}]").decode()
            if change == "order": altered["files"].reverse()
            destination = self.root / change
            with self.subTest(change=change), self.assertRaises(ValueError):
                corpus.extract_bundle(corpus.encode_json(altered), destination, 2, 3)
            self.assertFalse(destination.exists())

    def test_invalid_source_rows_are_rejected_without_echoing_content(self):
        for raw in [b"[null]", b"{}", b"[]", b"[{\"bad\":NaN}]", b"private_marker: malformed"]:
            with self.subTest(raw=raw), self.assertRaises(ValueError) as captured:
                corpus.source_rows(raw)
            self.assertNotIn("private_marker", str(captured.exception))

    def test_ciphertext_header_nonce_and_tag_are_authenticated(self):
        encrypted = corpus.seal(self.bundle, self.key, "corpus", 2, 3)
        header_length = struct.unpack(">I", encrypted[8:12])[0]
        for position in [12 + header_length - 2, 12 + header_length, len(encrypted) - 1]:
            corrupted = bytearray(encrypted)
            corrupted[position] ^= 1
            with self.subTest(position=position), self.assertRaises(ValueError):
                corpus.unseal(bytes(corrupted), self.key, "corpus", 2, 3)
        for corrupted in [encrypted[:-1], encrypted + b"x", b"invalid"]:
            with self.assertRaises(ValueError):
                corpus.unseal(corrupted, self.key, "corpus", 2, 3)
        with self.assertRaisesRegex(ValueError, "authentication"):
            corpus.unseal(encrypted, bytes(reversed(self.key)), "corpus", 2, 3)

    def test_purpose_and_expected_counts_cannot_be_confused(self):
        encrypted = corpus.seal(self.bundle, self.key, "corpus", 2, 3)
        for purpose, files, records in [("report", 2, 3), ("corpus", 3, 3), ("corpus", 2, 4)]:
            with self.subTest(purpose=purpose, files=files, records=records), self.assertRaises(ValueError):
                corpus.unseal(encrypted, self.key, purpose, files, records)

    def test_valid_authenticated_gzip_cannot_exceed_declared_plaintext_size(self):
        from cryptography.hazmat.primitives.ciphers.aead import AESGCM
        compressed = gzip.compress(b"x" * 100_000, mtime=0)
        header = corpus.encode_json({"schemaVersion": 1, "purpose": "logs", "compression": "gzip",
            "plaintextBytes": 1, "plaintextSHA256": corpus.sha256(b"x"), "compressedBytes": len(compressed),
            "fileCount": 2, "recordCount": 3})
        prefix = corpus.MAGIC + struct.pack(">I", len(header)) + header
        nonce = bytes(range(12))  # Public negative-test vector only.
        encrypted = prefix + nonce + AESGCM(self.key).encrypt(nonce, compressed, prefix)
        with self.assertRaisesRegex(ValueError, "Plaintext bytes"):
            corpus.unseal(encrypted, self.key, "logs", 2, 3)

    def test_report_encryption_preserves_all_not_run_rows(self):
        raw = corpus.encode_json(self.report())
        corpus.validate_report(raw, self.manifest)
        encrypted = corpus.seal(raw, self.key, "report", 2, 3)
        restored = corpus.unseal(encrypted, self.key, "report", 2, 3)
        corpus.validate_report(restored, self.manifest)
        self.assertEqual(raw, restored)

    def test_media_extraction_remains_distinct_from_verified_playback(self):
        report = self.report()
        report["mode"] = "live"
        report["selectedRecords"] = 1
        report["rows"][0].update(status="mediaExtracted", playbackVerified=False)
        raw = corpus.encode_json(report)
        corpus.validate_report(raw, self.manifest)
        restored = corpus.unseal(corpus.seal(raw, self.key, "report", 2, 3), self.key, "report", 2, 3)
        self.assertEqual(json.loads(restored)["rows"][0]["status"], "mediaExtracted")
        self.assertFalse(json.loads(restored)["rows"][0]["playbackVerified"])

    def test_report_missing_duplicate_or_foreign_occurrences_fail(self):
        for change in ["missing", "duplicate", "sha", "index", "status"]:
            report = self.report()
            if change == "missing": report["rows"].pop()
            if change == "duplicate": report["rows"][1] = copy.deepcopy(report["rows"][0])
            if change == "sha": report["rows"][0]["fileSHA"] = "0" * 64
            if change == "index": report["rows"][0]["index"] = -1
            if change == "status": report["rows"][0]["status"] = "assumedPassed"
            with self.subTest(change=change), self.assertRaises(ValueError):
                corpus.validate_report(corpus.encode_json(report), self.manifest)

    def test_binary_log_archive_round_trip(self):
        raw = b"\x00\xffsynthetic log archive\r\n" * 3
        encrypted = corpus.seal(raw, self.key, "logs", 2, 3)
        self.assertEqual(corpus.unseal(encrypted, self.key, "logs", 2, 3), raw)

    def test_existing_outputs_and_repository_plaintext_are_rejected(self):
        destination = self.root / "output"
        destination.write_bytes(b"keep")
        with self.assertRaises(ValueError): corpus.write_new(destination, b"replace")
        self.assertEqual(destination.read_bytes(), b"keep")
        with self.assertRaises(ValueError): corpus.require_external_plaintext(corpus.REPOSITORY_ROOT / "private.json")

    def test_input_size_limit_and_wrong_cipher_pin_reject_before_writing(self):
        original = self.root / "oversized"
        original.write_bytes(b"12345")
        with self.assertRaises(ValueError): corpus.read_bounded(original, 4)
        encrypted = self.root / "fixture.enc"
        encrypted.write_bytes(corpus.seal(self.bundle, self.key, "corpus", 2, 3))
        destination = self.root / "must-not-exist"
        with patch.dict(os.environ, {"FIXTURE_CORPUS_KEY": base64.b64encode(self.key).decode()}), redirect_stderr(io.StringIO()):
            result = corpus.main(["decrypt-corpus", "--input", str(encrypted), "--input-sha256", "0" * 64,
                                  "--output-dir", str(destination), "--key-env", "FIXTURE_CORPUS_KEY",
                                  "--expected-files", "2", "--expected-records", "3"])
        self.assertEqual(result, 1)
        self.assertFalse(destination.exists())

    def test_key_errors_do_not_print_environment_values(self):
        for invalid in ["secret-not-base64", base64.b64encode(b"short").decode(), base64.b64encode(self.key).decode() + "\n"]:
            with patch.dict(os.environ, {"FIXTURE_CORPUS_KEY": invalid}):
                captured = io.StringIO()
                with redirect_stderr(captured):
                    code = corpus.main(["pack", "--key-env", "FIXTURE_CORPUS_KEY"])
                self.assertEqual(code, 1)
                self.assertNotIn(invalid, captured.getvalue())

    def test_cli_pack_and_decrypt_verify_pinned_cipher_digest(self):
        encrypted = self.root / "fixture.enc"
        destination = self.root / "from-cli"
        common = ["--key-env", "FIXTURE_CORPUS_KEY", "--expected-files", "2", "--expected-records", "3"]
        output = io.StringIO()
        with patch.dict(os.environ, {"FIXTURE_CORPUS_KEY": base64.b64encode(self.key).decode()}), redirect_stdout(output):
            self.assertEqual(corpus.main(["pack", "--manifest", str(self.inventory), "--output", str(encrypted)] + common), 0)
            expected = corpus.sha256(encrypted.read_bytes())
            self.assertEqual(corpus.main(["decrypt-corpus", "--input", str(encrypted), "--input-sha256", expected,
                                         "--output-dir", str(destination)] + common), 0)
        self.assertNotIn("fixture_private_marker", output.getvalue())
        self.assertNotIn(base64.b64encode(self.key).decode(), output.getvalue())
        self.assertTrue((Path(str(encrypted) + ".manifest.json")).is_file())
        self.assertEqual((destination / "sources-01.json").read_bytes(), self.originals[0])

    @unittest.skipUnless(sys.platform == "darwin" and shutil.which("swift"), "macOS Swift/CryptoKit interop requires a macOS runner")
    def test_macos_cryptokit_decrypts_python_and_encrypts_reports_and_logs(self):
        encrypted = self.root / "fixture.enc"
        encrypted.write_bytes(corpus.seal(self.bundle, self.key, "corpus", 2, 3))
        destination = self.root / "swift-output"
        environment = dict(os.environ, FIXTURE_CORPUS_KEY=base64.b64encode(self.key).decode())
        script = Path(__file__).with_name("private_corpus_cipher.swift")
        common = ["--key-env", "FIXTURE_CORPUS_KEY", "--expected-files", "2", "--expected-records", "3"]

        def swift(command):
            result = subprocess.run(["swift", str(script)] + command + common, env=environment,
                                    capture_output=True, text=True, timeout=90)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("fixture_private_marker", result.stdout + result.stderr)

        swift(["decrypt-corpus", "--input", str(encrypted), "--input-sha256", corpus.sha256(encrypted.read_bytes()),
               "--output-dir", str(destination)])
        self.assertEqual((destination / "sources-01.json").read_bytes(), self.originals[0])
        for purpose, command in [("report", "encrypt-report"), ("logs", "seal-logs")]:
            report = self.report()
            report["rows"][0].update(status="mediaExtracted", playbackVerified=False)
            raw = corpus.encode_json(report) if purpose == "report" else b"\x00\xfffixture log archive"
            original, sealed = self.root / (purpose + ".raw"), self.root / (purpose + ".enc")
            original.write_bytes(raw)
            options = [command, "--input", str(original), "--input-sha256", corpus.sha256(raw), "--output", str(sealed)]
            if purpose == "report": options += ["--manifest", str(destination / "manifest.json")]
            swift(options)
            self.assertEqual(corpus.unseal(sealed.read_bytes(), self.key, purpose, 2, 3), raw)


if __name__ == "__main__":
    unittest.main()
