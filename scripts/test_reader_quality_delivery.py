"""Check desktop publication and the same-tree IPA gate without building a package."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import deliver_reader_quality as delivery


class ReaderQualityDeliveryTests(unittest.TestCase):
    def test_package_name_uses_verified_metadata_instead_of_historical_release(self):
        self.assertEqual(delivery.package_filename({"CFBundleShortVersionString": "1.1.8",
            "CFBundleVersion": "138"}, "a" * 40), "SourceReadSwift-1.1.8-build138-aaaaaaa-unsigned.ipa")

    def test_rejects_a_candidate_when_runtime_changes_are_not_in_its_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "LATEST.json").write_text(json.dumps({"head": "old", "tree": "old-tree"}), encoding="utf8")
            with patch.object(delivery, "EVIDENCE", root), \
                 patch.object(delivery, "snapshot_tree", return_value=("new-tree", []), create=True):
                with self.assertRaisesRegex(RuntimeError, "Current workspace differs"):
                    delivery.read_candidate()

    def test_publish_is_idempotent_and_never_replaces_a_different_ipa(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "verified.ipa"
            source.write_bytes(b"verified package")
            desktop = root / "Desktop"
            desktop.mkdir()
            target = desktop / "reader.ipa"
            digest = hashlib.sha256(source.read_bytes()).hexdigest()
            delivery.publish_verified_ipa(source, target, digest)
            delivery.publish_verified_ipa(source, target, digest)
            self.assertEqual(target.read_bytes(), source.read_bytes())
            target.write_bytes(b"another candidate")
            with self.assertRaisesRegex(RuntimeError, "already contains"):
                delivery.publish_verified_ipa(source, target, digest)
            self.assertEqual(target.read_bytes(), b"another candidate")
            self.assertEqual(list(desktop.iterdir()), [target])

    def test_green_job_with_skipped_native_unit_tests_does_not_pass_release_gate(self):
        jobs = [
            {"name": "build", "conclusion": "success", "steps": [{"name": "Test", "conclusion": "success"}]},
            {"name": "native-tabs", "conclusion": "success", "steps": [
                {"name": "iOS26 native tab runtime regression", "conclusion": "skipped"},
                {"name": "Exercise real reader settings UI on iOS26", "conclusion": "success"},
                {"name": "Exercise reader chapter continuity on iOS26", "conclusion": "success"},
                {"name": "Exercise reader return gestures on iOS26", "conclusion": "success"},
            ]},
        ]
        with self.assertRaisesRegex(RuntimeError, "iOS26 native tab runtime regression"):
            delivery.require_native_steps(jobs)
        jobs[1]["steps"][0]["conclusion"] = "success"
        with self.assertRaisesRegex(RuntimeError, "twenty native reader return cycles"):
            delivery.require_native_steps(jobs)
        jobs[1]["steps"].append({"name": "Exercise twenty native reader return cycles on iOS26", "conclusion": "success"})
        with self.assertRaisesRegex(RuntimeError, "Legacy reader.*16.4"):
            delivery.require_native_steps(jobs)
        jobs.append({"name": "Legacy reader (iOS 16.4)", "conclusion": "success", "steps": [
            {"name": "Verify legacy reader open cancel and return", "conclusion": "success"},
        ]})
        with self.assertRaisesRegex(RuntimeError, "Legacy reader.*17.5"):
            delivery.require_native_steps(jobs)
        jobs.append({"name": "Legacy reader (iOS 17.5)", "conclusion": "success", "steps": [
            {"name": "Verify legacy reader open cancel and return", "conclusion": "skipped"},
        ]})
        with self.assertRaisesRegex(RuntimeError, "Verify legacy reader open cancel and return"):
            delivery.require_native_steps(jobs)
        jobs[-1]["steps"][0]["conclusion"] = "success"
        delivery.require_native_steps(jobs)

    def test_bad_staging_hash_never_publishes_a_visible_ipa(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "damaged.ipa"
            source.write_bytes(b"incomplete")
            target = root / "desktop.ipa"
            with self.assertRaisesRegex(RuntimeError, "staging hash"):
                delivery.publish_verified_ipa(source, target, "wrong")
            self.assertFalse(target.exists())
            self.assertEqual(list(root.iterdir()), [source])
