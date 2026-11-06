"""Keep advertised and streamed comic byte limits enforced before image decode.
Usage: python -m unittest discover -s scripts -p test_comic_transport_boundary.py
"""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class ComicTransportBoundaryTests(unittest.TestCase):
    def test_comic_header_limit_does_not_depend_only_on_expected_length(self):
        source = (ROOT / "SourceReadSwift/Shared/DesignSystem/ComicImageTransport.swift").read_text(encoding="utf8")
        self.assertTrue('value(forHTTPHeaderField: "Content-Length")' in source,
                        "Reject an advertised oversized response even if expectedContentLength is unknown")
