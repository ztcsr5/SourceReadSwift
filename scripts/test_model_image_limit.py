"""Verify model previews stay under 1 MiB and preserve original evidence.

Usage: python -B -X utf8 -m unittest discover -s scripts -p 'test_model_image_limit.py'
"""
import hashlib
from pathlib import Path
import random
import tempfile
import unittest

from PIL import Image

from prepare_model_image import MAX_IMAGE_BYTES, prepare_model_image


class ModelImageLimitTests(unittest.TestCase):
    def test_large_screenshot_is_bounded_and_original_is_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "screenshot.png"
            pixels = random.Random(137).randbytes(1200 * 2600 * 3)
            Image.frombytes("RGB", (1200, 2600), pixels).save(source)
            original_hash = hashlib.sha256(source.read_bytes()).hexdigest()
            self.assertGreater(source.stat().st_size, MAX_IMAGE_BYTES)
            receipt = prepare_model_image(source, Path(directory) / "previews")
            preview = Path(receipt["path"])
            self.assertLessEqual(preview.stat().st_size, 1_048_576)
            self.assertEqual(receipt["bytes"], preview.stat().st_size)
            self.assertEqual(hashlib.sha256(source.read_bytes()).hexdigest(), original_hash)
            with Image.open(preview) as picture:
                picture.verify()

    def test_small_image_is_reused_without_loss(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "small.png"
            Image.new("RGBA", (40, 60), (20, 40, 80, 120)).save(source)
            receipt = prepare_model_image(source, Path(directory) / "previews")
            self.assertEqual(Path(receipt["path"]), source.resolve())
            self.assertFalse((Path(directory) / "previews").exists())

    def test_invalid_image_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "invalid.png"
            source.write_bytes(b"not a screenshot")
            with self.assertRaises(ValueError):
                prepare_model_image(source, Path(directory) / "previews")


if __name__ == "__main__":
    unittest.main()
