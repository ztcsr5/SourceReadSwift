"""Render the three edition pictograms at all existing iOS icon sizes.

Usage: python -B -X utf8 scripts/render_edition_icons.py
Uses Pillow and the existing path drawing routine. Never edits any manifest.
"""
import json

from PIL import Image, ImageDraw

from generate_master_app_icon import ASSETS, SCALE, bezier_shape

EDGE = 1024


def polygon(pen, points, fill):
    pen.polygon([(x * SCALE, y * SCALE) for x, y in points], fill=fill)


def ellipse(pen, box, fill, outline=None, width=1):
    pen.ellipse(tuple(value * SCALE for value in box), fill=fill, outline=outline, width=width * SCALE)


def draw_ink(pen):
    pen.arc((221 * SCALE, 218 * SCALE, 803 * SCALE, 800 * SCALE), start=21, end=333,
            fill="#242424", width=28 * SCALE)
    ridge = [("M", 306, 655), ("C", 372, 629, 437, 564, 493, 420),
             ("C", 522, 451, 563, 546, 610, 567), ("C", 649, 584, 697, 623, 738, 674),
             ("C", 580, 640, 479, 628, 306, 655)]
    pen.polygon(bezier_shape(ridge), fill="#292929")
    polygon(pen, [(444, 587), (495, 498), (479, 573)], "#ECECEC")
    polygon(pen, [(563, 715), (702, 697), (676, 721), (578, 728)], "#646464")


def draw_blade(pen):
    polygon(pen, [(257, 748), (675, 290), (794, 236), (743, 350), (316, 778)], "#F6F6F6")
    polygon(pen, [(361, 665), (755, 254), (672, 371), (399, 640)], "#101010")
    polygon(pen, [(239, 580), (267, 542), (489, 735), (462, 760)], "#B9B9B9")
    polygon(pen, [(251, 805), (620, 651), (681, 633), (625, 675), (266, 820)], "#646464")


def draw_bunny(pen):
    ellipse(pen, (157, 156, 870, 869), "#F8BBCF")
    face = [("M", 373, 451), ("C", 302, 365, 286, 267, 345, 246),
            ("C", 397, 222, 441, 295, 471, 406), ("C", 512, 394, 555, 399, 578, 413),
            ("C", 603, 306, 650, 246, 692, 271), ("C", 748, 296, 713, 380, 668, 464),
            ("C", 754, 505, 794, 650, 666, 715), ("C", 550, 773, 401, 748, 333, 664),
            ("C", 276, 598, 300, 507, 373, 451)]
    pen.polygon(bezier_shape(face), fill="#FFF6EF")
    pen.line(bezier_shape(face), fill="#612944", width=13 * SCALE, joint="curve")
    ellipse(pen, (415, 547, 441, 578), "#612944")
    ellipse(pen, (580, 547, 606, 578), "#612944")
    ellipse(pen, (371, 579, 423, 601), "#FCA5B9")
    ellipse(pen, (605, 579, 657, 601), "#FCA5B9")
    pen.arc((487 * SCALE, 567 * SCALE, 535 * SCALE, 610 * SCALE), 0, 180, fill="#612944", width=10 * SCALE)
    polygon(pen, [(330, 653), (437, 630), (512, 667), (587, 630), (694, 653),
                  (669, 751), (591, 741), (512, 777), (437, 741), (353, 751)], "#9A2854")
    polygon(pen, [(512, 667), (587, 630), (694, 653), (669, 751), (591, 741), (512, 777)], "#BA3F69")


EDITIONS = {
    "Shuimo": ("#F4F4F4", draw_ink),
    "Wuxia": ("#101010", draw_blade),
    "Kawaii": ("#FFE9EB", draw_bunny),
}


def render():
    """Write opaque sizes that Xcode already declares, plus matching internal marks."""
    for name, (paper, draw) in EDITIONS.items():
        origin = Image.new("RGB", (EDGE * SCALE, EDGE * SCALE), paper)
        draw(ImageDraw.Draw(origin))
        master = origin.resize((EDGE, EDGE), Image.Resampling.LANCZOS)
        bundle = ASSETS / f"AppIcon{name}.appiconset"
        manifest = json.loads((bundle / "Contents.json").read_text(encoding="utf8"))
        for image in manifest["images"]:
            filename = image.get("filename")
            if not filename:
                continue
            size = EDGE if filename == "AppIcon-1024.png" else int(filename.removeprefix("Icon-").removesuffix(".png"))
            master.resize((size, size), Image.Resampling.LANCZOS).save(bundle / filename, optimize=True)
        mark = ASSETS / f"BrandMark{name}.imageset" / f"BrandMark{name}.png"
        # A 512 px PNG serves both the Settings preview and Shortcuts export.
        master.resize((512, 512), Image.Resampling.LANCZOS).save(mark, optimize=True)


if __name__ == "__main__":
    render()
