"""Build the bundled OFL desk-title fallback; requires fonttools==4.68.0.

Usage: python -B -X utf8 scripts/build_reading_desk_font.py <NotoSerifSC variable font>
Read the provenance record beside the resulting font. Normal app builds do
not use this script or download fonts.
"""
import argparse
import hashlib
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

EXPECTED = "050080d9255a86808f2945bffac582b31ef32bc36411ce29563b4961670c66f9"
POSTSCRIPT = "ReadingDeskSong-Regular"
FAMILY = "Reading Desk Song"

def title_characters():
    # GB2312 covers common Simplified Chinese. Include Latin, punctuation,
    # numbers and full-width forms for mixed-language catalogue titles.
    points = set(range(0x20, 0x250)) | set(range(0x2000, 0x2070))
    points.update(range(0x3000, 0x3040))
    points.update(range(0xFF00, 0xFFF0))
    for zone in range(0xA1, 0xF8):
        for position in range(0xA1, 0xFF):
            try:
                points.add(ord(bytes((zone, position)).decode("gb2312")))
            except UnicodeDecodeError:
                continue
    return points

def build(source, output):
    if hashlib.sha256(source.read_bytes()).hexdigest() != EXPECTED:
        raise ValueError("Unexpected source font SHA256; use the pinned upstream file")
    font = TTFont(source, recalcTimestamp=False)
    font = instantiateVariableFont(font, {"wght": 400}, inplace=True, updateFontNames=True)
    # Use the font designer's typographic metrics for compact two-line titles.
    vertical = font["OS/2"]
    font["hhea"].ascent = vertical.sTypoAscender
    font["hhea"].descent = vertical.sTypoDescender
    font["hhea"].lineGap = vertical.sTypoLineGap
    options = subset.Options()
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14, 16, 17]
    selection = subset.Subsetter(options=options)
    selection.populate(unicodes=title_characters())
    selection.subset(font)
    names = font["name"]
    replacement = {1: FAMILY, 2: "Regular", 3: POSTSCRIPT, 4: FAMILY + " Regular",
                   6: POSTSCRIPT, 16: FAMILY, 17: "Regular"}
    for record in names.names:
        if record.nameID in replacement:
            record.string = replacement[record.nameID]
    font.save(output)
    checked = TTFont(output)
    assert checked["name"].getDebugName(6) == POSTSCRIPT and "fvar" not in checked
    assert all(ord(character) in checked.getBestCmap() for character in "剑来凡人修仙传第１２卷夜航Lab2.0封印")
    print(f"{output}: {len(checked.getBestCmap())} codepoints, {output.stat().st_size} bytes, SHA256 {hashlib.sha256(output.read_bytes()).hexdigest()}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, default=Path("SourceReadSwift/Resources/Fonts") / (POSTSCRIPT + ".ttf"))
    args = parser.parse_args()
    build(args.source, args.output)
