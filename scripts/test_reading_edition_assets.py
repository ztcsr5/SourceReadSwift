"""Verify day/night contrast inputs and installed artwork/icon resources.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_reading_edition_assets.py
These measurements cover static tokens and images, not glass compositing.
"""
import json
from pathlib import Path
import re
import unittest

from PIL import Image, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "SourceReadSwift/App/Assets.xcassets"


def luminance(rgb: tuple[int, ...]) -> float:
    linear = [channel / 255 for channel in rgb]
    linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in linear]
    return sum(part * weight for part, weight in zip(linear, (0.2126, 0.7152, 0.0722)))


def palette_color(source: str, token: str, edition: str) -> tuple[int, ...]:
    section = source.split(f"var {token}: UInt32", 1)[1].split("\n    }", 1)[0]
    match = re.search(rf"case \.{edition}: return 0x([A-Fa-f0-9]{{6}})", section)
    if match is None:
        raise AssertionError(f"Missing {token} for {edition}")
    return tuple(bytes.fromhex(match[1]))


class ReadingEditionAssetsTests(unittest.TestCase):
    def test_selected_controls_have_contrast_in_both_appearances(self):
        source = (ROOT / "SourceReadSwift/Shared/DesignSystem/AppVisualTheme.swift").read_text(encoding="utf8")
        for edition in ("shuimo", "wuxia", "anime", "kawaii"):
            for accent, card in (("accentHex", "cardHex"), ("darkAccentHex", "darkCardHex")):
                with self.subTest(edition=edition, accent=accent):
                    ink = palette_color(source, accent, edition)
                    paper = palette_color(source, card, edition)
                    light, dark = sorted((luminance(ink), luminance(paper)), reverse=True)
                    self.assertGreaterEqual((light + 0.05) / (dark + 0.05), 4.5)
                    if edition in ("shuimo", "wuxia"):
                        self.assertEqual(len(set(ink)), 1)
                        self.assertEqual(len(set(paper)), 1)

    def test_ink_art_is_achromatic_and_all_editions_have_day_night_assets(self):
        for edition in ("Shuimo", "Wuxia", "Kawaii"):
            for period in ("Day", "Night"):
                name = f"Theme{edition}{period}"
                with self.subTest(name=name):
                    asset = CATALOG / f"{name}.imageset" / f"{name}.jpg"
                    with Image.open(asset) as art:
                        self.assertEqual(art.size, (768, 1360))
                        if edition != "Kawaii":
                            self.assertEqual(art.mode, "L")
                        head = art.convert("L").crop((30, 30, 738, 100))
                        value = ImageStat.Stat(head).mean[0]
                        if period == "Day":
                            self.assertGreater(value, 214)
                        else:
                            self.assertLess(value, 75)
                    self.assertLessEqual(asset.stat().st_size, 200_000)

    def test_full_icon_and_phone_sizes_are_opaque_for_each_edition(self):
        for edition in ("Shuimo", "Wuxia", "Kawaii", "InPageGlass", "AtelierRing", "ShuimoPeak", "WuxiaSword"):
            folder = CATALOG / f"AppIcon{edition}.appiconset"
            manifest = json.loads((folder / "Contents.json").read_text(encoding="utf8"))
            paths = {entry["filename"] for entry in manifest["images"] if "filename" in entry}
            self.assertIn("Icon-180.png", paths)
            self.assertIn("AppIcon-1024.png", paths)
            for name in paths:
                with self.subTest(edition=edition, name=name), Image.open(folder / name) as icon:
                    side = 1024 if name == "AppIcon-1024.png" else int(name[5:-4])
                    self.assertEqual(icon.size, (side, side))
                    self.assertEqual(icon.mode, "RGB")

    def test_export_and_brand_mark_match_the_packaged_desktop_icon_artwork(self):
        for suffix in ("", "Classic", "Klein", "Shuimo", "Wuxia", "Anime", "Kawaii", "Noir",
                       "InPageGlass", "AtelierRing", "ShuimoPeak", "WuxiaSword"):
            art = CATALOG / f"AppIcon{suffix}.appiconset" / "AppIcon-1024.png"
            mark = CATALOG / f"BrandMark{suffix}.imageset" / f"BrandMark{suffix}.png"
            with self.subTest(suffix=suffix), Image.open(art) as app_icon, Image.open(mark) as brand:
                resized = app_icon.convert("RGB").resize(brand.size, Image.Resampling.LANCZOS)
                self.assertIsNone(ImageChops.difference(resized, brand.convert("RGB")).getbbox())


if __name__ == "__main__":
    unittest.main()
