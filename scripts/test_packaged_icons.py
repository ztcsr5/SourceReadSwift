"""Test the icon manifest gate and the committed artwork sizes, without Xcode."""
import json
from pathlib import Path
import struct
import unittest

from verify_packaged_icons import expected_alternates, verify_catalog_rows, verify_icon_manifest

ROOT = Path(__file__).resolve().parents[1]
PROJECT = (ROOT / "project.yml").read_text(encoding="utf-8")
ASSETS = ROOT / "SourceReadSwift/App/Assets.xcassets"


def fixture_icons() -> dict:
    return {"CFBundlePrimaryIcon": {"CFBundleIconName": "AppIcon"},
            "CFBundleAlternateIcons": {name: {"CFBundleIconName": name}
                                      for name in expected_alternates(PROJECT)}}


class PackagedIconTests(unittest.TestCase):
    def test_manifest_checks_each_idiom_and_car_checks_actual_names(self):
        manifest = {"CFBundleIcons": fixture_icons(), "CFBundleIcons~ipad": fixture_icons()}
        alternates = verify_icon_manifest(manifest, PROJECT)
        self.assertEqual(len(alternates), 7)
        rows = [{"Name": name} for name in ["AppIcon", *alternates]]
        verify_catalog_rows(rows, alternates)
        with self.assertRaisesRegex(ValueError, "Missing compiled"):
            verify_catalog_rows(rows[:-1], alternates)
        manifest["CFBundleIcons~ipad"]["CFBundleAlternateIcons"].pop(alternates[0])
        with self.assertRaisesRegex(ValueError, "CFBundleIcons~ipad"):
            verify_icon_manifest(manifest, PROJECT)

    def test_each_alternate_supplies_renditions_at_home_screen_sizes(self):
        for name in expected_alternates(PROJECT):
            directory = ASSETS / f"{name}.appiconset"
            slots = json.loads((directory / "Contents.json").read_text(encoding="utf-8"))["images"]
            for idiom, size, scale in (("iphone", "60x60", "2x"), ("iphone", "60x60", "3x"),
                                      ("ipad", "76x76", "2x"), ("ipad", "83.5x83.5", "2x")):
                self.assertIn((idiom, size, scale), {(slot["idiom"], slot["size"], slot["scale"]) for slot in slots})
            for slot in slots:
                path = directory / slot["filename"]
                # Read only the PNG IHDR; CI separately validates its compiled rendition.
                header = path.read_bytes()[:26]
                self.assertEqual(header[:8], b"\x89PNG\r\n\x1a\n")
                pixels = int(float(slot["size"].split("x")[0]) * int(slot["scale"][:-1]))
                self.assertEqual(struct.unpack(">II", header[16:24]), (pixels, pixels), str(path))
                self.assertEqual(header[25], 2, f"{path} must be opaque RGB")
