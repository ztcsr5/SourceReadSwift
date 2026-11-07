"""Render the reproducible Xi Guang brand mark and a small-size review sheet.

Usage: python -B -X utf8 scripts/generate_master_app_icon.py
Requires the existing Pillow toolchain; no network or image API is used.
"""
import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'SourceReadSwift/App/Assets.xcassets'
PALETTE = {'cocoa': '#392B2B', 'periwinkle': '#B9BCF0', 'blush': '#E8B5BC', 'moss': '#82917C'}
SCALE = 2
EDGE = 1024 * SCALE


def ribbon_mask(start: float, end: float) -> Image.Image:
    """Build an oblique aperture with a generous countershape at home-screen size."""
    angle = math.radians(-32)
    vertices = []
    for rx, ry, samples in [(285, 369, range(301)), (132, 223, range(300, -1, -1))]:
        for step in samples:
            t = math.radians(start + (end - start) * step / 300)
            x, y = rx * math.cos(t), ry * math.sin(t)
            vertices.append(((512 + x * math.cos(angle) - y * math.sin(angle)) * SCALE,
                             (505 + x * math.sin(angle) + y * math.cos(angle)) * SCALE))
    mask = Image.new('L', (EDGE, EDGE))
    ImageDraw.Draw(mask).polygon(vertices, fill=255)
    return mask


def shade(top: tuple, bottom: tuple) -> Image.Image:
    """Use one broad lighting direction, avoiding tiny decorative details."""
    strip = Image.new('RGB', (1, EDGE))
    for y in range(EDGE):
        t = y / (EDGE - 1)
        strip.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)))
    return strip.resize((EDGE, EDGE))


def create_master_app_icon() -> None:
    """Write the opaque iOS icon and the matching in-app brand asset."""
    canvas = shade((75, 56, 53), (39, 30, 35))
    body = ribbon_mask(157, 480)
    shadow = Image.new('L', (EDGE, EDGE))
    shadow.paste(body, (12 * SCALE, 22 * SCALE))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22 * SCALE)).point(lambda p: p * 0.45)
    canvas.paste(Image.new('RGB', canvas.size, '#17131B'), mask=shadow)
    canvas.paste(shade((227, 225, 255), (111, 115, 183)), mask=body)
    lower = ribbon_mask(60, 145)
    canvas.paste(shade((250, 220, 218), (199, 141, 158)), mask=lower)
    # A narrow moss bevel gives the cut a distinct material without becoming a fourth symbol.
    bevel = ribbon_mask(146, 153)
    canvas.paste(shade((172, 184, 151), (105, 126, 105)), mask=bevel)
    icon = canvas.resize((1024, 1024), Image.Resampling.LANCZOS).convert('RGB')
    icon_path = ASSETS / 'AppIcon.appiconset/AppIcon-1024.png'
    icon.save(icon_path, optimize=True)
    brand = ASSETS / 'BrandMark.imageset'
    brand.mkdir(exist_ok=True)
    icon.resize((192, 192), Image.Resampling.LANCZOS).save(brand / 'BrandMark.png', optimize=True)
    (brand / 'Contents.json').write_text(json.dumps({'images': [{'filename': 'BrandMark.png', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n', encoding='utf8')
    review = ROOT / 'docs/project-audit-20261108'
    review.mkdir(exist_ok=True)
    sheet = Image.new('RGB', (1060, 700), '#F5F0EA')
    sheet.paste(icon.resize((600, 600), Image.Resampling.LANCZOS), (40, 40))
    pen = ImageDraw.Draw(sheet)
    for x, size in [(700, 120), (860, 60), (960, 40)]:
        thumb = icon.resize((size, size), Image.Resampling.LANCZOS)
        crop = Image.new('L', (size, size))
        ImageDraw.Draw(crop).rounded_rectangle((0, 0, size, size), radius=size * 0.225, fill=255)
        sheet.paste(thumb, (x, 70), crop)
        pen.text((x, 210), f'{size} px', fill='#392B2B')
    for index, (name, color) in enumerate(PALETTE.items()):
        y = 290 + index * 76
        pen.rounded_rectangle((700, y, 748, y + 48), radius=12, fill=color)
        pen.text((766, y + 8), f'{name}\n{color}', fill='#392B2B', spacing=5)
    sheet.save(review / 'ICON-REVIEW.png', optimize=True)
    print(json.dumps({'icon': str(icon_path), 'bytes': icon_path.stat().st_size, 'mode': icon.mode,
                      'size': icon.size, 'palette': PALETTE}, ensure_ascii=False))


if __name__ == '__main__':
    create_master_app_icon()
