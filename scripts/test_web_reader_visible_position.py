"""Replay the document's actual visible-node selection at chapter boundaries.

Usage: python -B -X utf8 -m unittest discover -s scripts -p test_web_reader_visible_position.py
"""
import json
from pathlib import Path
import subprocess
import unittest


ROOT = Path(__file__).resolve().parents[1]


class WebReaderVisiblePositionTests(unittest.TestCase):
    def test_whitespace_after_previous_chapter_does_not_report_offscreen_prose(self):
        source = (ROOT / "SourceReadSwift/Features/Reader/WebReaderDocument.swift").read_text(encoding="utf8")
        start = source.index("      function metricAt(y) {")
        end = source.index("      function captureAnchor()", start)
        script = """
        const window = {scrollY: 0};
        const boxes = [[0,40],[60,240],[340,400],[420,640]];
        const state = {nodes: boxes.map(([top,bottom],index)=>({index,
          getBoundingClientRect:()=>({top,bottom,height:bottom-top})}))};
        const nodeMetric = element => ({index:element.index});
        """ + source[start:end] + """
        console.log(JSON.stringify([-10,0,100,239,240,300,340,500,700].map(y=>metricAt(y).index)));
        """
        outcome = subprocess.run(["node", "-e", script], cwd=ROOT, capture_output=True,
                                 text=True, encoding="utf8", timeout=10, check=True)
        self.assertEqual(json.loads(outcome.stdout), [0,0,1,1,2,2,2,3,3])


if __name__ == "__main__":
    unittest.main()
