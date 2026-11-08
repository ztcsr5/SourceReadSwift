"""Validate the selected local icon; run: python -m unittest discover -s scripts -p test_master_app_icon.py."""
import unittest

import numpy as np
from PIL import Image, ImageColor

from generate_master_app_icon import ASSETS, PALETTES, render_interlaced_icon


class MasterAppIconTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.icon = render_interlaced_icon('pine')
        cls.colours = [ImageColor.getrgb(value) for value in PALETTES['pine'][:2]]

    def test_master_is_opaque_rgb_at_required_size(self):
        self.assertEqual(self.icon.mode, 'RGB')
        self.assertEqual(self.icon.size, (1024, 1024))

    def test_original_pair_dominates_without_blended_colour_fields(self):
        pixels = np.asarray(self.icon)
        coverage = sum(np.all(pixels == colour, axis=2).mean() for colour in self.colours)
        self.assertGreater(coverage, .93)
        for colour in self.colours:
            self.assertGreater(np.all(pixels == colour, axis=2).mean(), .3)

    def test_corners_remain_full_bleed_not_prebaked_system_rounding(self):
        for x in (0, 1023):
            self.assertEqual(self.icon.getpixel((x, 0)), self.colours[0])
            self.assertEqual(self.icon.getpixel((x, 1023)), self.colours[1])

    def test_small_exports_keep_both_contrasting_fields(self):
        for size in (40, 60, 120):
            pixels = np.asarray(self.icon.resize((size, size), Image.Resampling.LANCZOS)).astype(int)
            for colour in self.colours:
                with self.subTest(size=size, colour=colour):
                    self.assertGreater((np.max(abs(pixels-colour), axis=2) <= 3).mean(), .25)

    def test_committed_assets_match_reproducible_master(self):
        with Image.open(ASSETS/'AppIcon.appiconset/AppIcon-1024.png') as master:
            self.assertEqual(master.mode, 'RGB')
            self.assertEqual(master.tobytes(), self.icon.tobytes())
        with Image.open(ASSETS/'BrandMark.imageset/BrandMark.png') as brand:
            expected = self.icon.resize((192, 192), Image.Resampling.LANCZOS)
            self.assertEqual(brand.size, expected.size)
            self.assertEqual(brand.tobytes(), expected.tobytes())


if __name__ == '__main__':
    unittest.main()
