"""Render a labeled review sheet from preserved XCTest attachment receipts.

Usage: python -B -X utf8 scripts/render_audit_contact_sheet.py <RECEIPT> <OUTPUT> <LABEL_REGEX>
Original images are never changed. Run prepare_model_image.py before viewing the sheet.
"""
import argparse
import json
from pathlib import Path
import re

from PIL import Image, ImageDraw, ImageFont


def render_sheet(receipt: Path, output: Path, pattern: str) -> int:
    """Select up to twelve labeled PNGs and write an opaque review sheet."""
    record = json.loads(receipt.read_text(encoding="utf8"))
    groups = record if isinstance(record, list) else [record]
    candidates = [shot for group in groups for shot in group.get("screenshots", group.get("attachments", []))]
    selected = [shot for shot in candidates if re.search(pattern, shot["label"])
                and Path(shot.get("path", "")).suffix.lower() == ".png"]
    if not 1 <= len(selected) <= 12:
        raise ValueError(f"Select 1–12 PNGs, matched {len(selected)}")
    width, height, columns = 280, 650, min(4, len(selected))
    sheet = Image.new("RGB", (width * columns, height * ((len(selected) + columns - 1) // columns)), "#e9e9e9")
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=12)
    for index, shot in enumerate(selected):
        x, y = (index % columns) * width, (index // columns) * height
        with Image.open(shot["path"]) as original:
            preview = original.convert("RGB")
            preview.thumbnail((width - 12, height - 60))
            sheet.paste(preview, (x + (width - preview.width) // 2, y + 50))
        label = shot["label"].split("_0_", 1)[0]
        for line in range(3):
            draw.text((x + 6, y + 5 + 14 * line), label[38 * line:38 * (line + 1)], fill="#111111", font=font)
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output)
    return len(selected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("pattern")
    arguments = parser.parse_args()
    count = render_sheet(arguments.receipt, arguments.output, arguments.pattern)
    print(json.dumps({"path": str(arguments.output.resolve()), "images": count}))
