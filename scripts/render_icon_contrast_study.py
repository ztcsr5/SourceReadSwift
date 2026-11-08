"""Render stronger peach/moss compositions without replacing app assets.

Usage: python -B -X utf8 scripts/render_icon_contrast_study.py
Uses the existing Pillow and NumPy design toolchain.
"""
import json

import numpy as np
from PIL import Image, ImageColor, ImageDraw

from generate_master_app_icon import EDGE, PALETTES, REVIEW, draw_fold, load_review_font, paste_icon


def render_expressive_icon(variant: str, palette: str = 'peach') -> Image.Image:
    """Keep the paired pigments while varying crop, polarity and curved field placement."""
    canvas = Image.new('RGB', (EDGE, EDGE), 'black')
    draw_fold(ImageDraw.Draw(canvas), 'white', 'black')
    sizes = {'bold': (1740, -24), 'deep': (1740, -24), 'folded': (1740, -24)}
    size, angle = sizes[variant]
    mask = canvas.convert('L').resize((size, size), Image.Resampling.LANCZOS)
    mask = mask.rotate(angle, resample=Image.Resampling.BICUBIC)
    inset = (size-1024)//2
    mask = np.asarray(mask.crop((inset, inset, inset+1024, inset+1024)))/255.0
    y, x = np.mgrid[:1024, :1024]
    boundary = 520+165*np.sin((x-100)/1100*np.pi)
    field = np.clip((y-boundary)/2+.5, 0, 1)
    mix = mask*(1-field)+(1-mask)*field
    if variant in ('deep', 'folded'):
        mix = 1-mix
    peach, moss, _ = PALETTES[palette]
    first, second = np.array(ImageColor.getrgb(peach)), np.array(ImageColor.getrgb(moss))
    rgb = first*(1-mix[..., None])+second*mix[..., None]
    if variant == 'folded':
        # A narrow cast fold follows the same field edge, not the whole icon outline.
        shadow = np.exp(-np.maximum(y-boundary, 0)/24)*(y >= boundary)
        highlight = np.exp(-np.maximum(boundary-y, 0)/5)*(y < boundary)
        rgb *= (1-.22*shadow)[..., None]
        rgb += (255-rgb)*(.10*highlight)[..., None]
    return Image.fromarray(np.uint8(np.clip(rgb, 0, 255)), 'RGB')


def render_contrast_study() -> dict:
    """Present three stronger versions and retain their full-resolution masters."""
    REVIEW.mkdir(exist_ok=True)
    sheet = Image.new('RGB', (1512, 860), '#F5F1EB')
    pen = ImageDraw.Draw(sheet)
    pen.text((56, 40), '桃粉 × 苔青 / 加强视觉张力', font=load_review_font(32), fill='#25211E')
    pen.text((56, 98), '沿用 C 的双色反转，放大出界、加大倾角；再比较正负色与一层折面。',
             font=load_review_font(19), fill='#625B55')
    titles = {'bold': ('C1 / 放大构图', '桃粉为底，更舒展'),
              'deep': ('C2 / 深色主导', '苔青为底，更鲜明'),
              'folded': ('C3 / 立体折面', '在 C2 上增加一层深度')}
    for index, (variant, (title, description)) in enumerate(titles.items()):
        x = 56+index*488
        icon = render_expressive_icon(variant)
        paste_icon(sheet, icon, (x, 168), 424)
        pen.text((x, 626), title, font=load_review_font(26), fill='#25211E')
        pen.text((x, 671), description, font=load_review_font(19), fill='#625B55')
        paste_icon(sheet, icon, (x, 724), 60)
        paste_icon(sheet, icon, (x+84, 736), 40)
        pen.text((x+149, 742), '60 / 40 px', font=load_review_font(16), fill='#625B55')
        icon.save(REVIEW/f'ICON-EXPRESSIVE-{variant}.png', optimize=True)
    path = REVIEW/'ICON-CONTRAST-STUDY.png'
    sheet.save(path, optimize=True)
    return {'preview': str(path)}


def render_added_palettes() -> dict:
    """Compare the newly requested colours using the same graphic composition."""
    from generate_master_app_icon import render_experimental_icon
    sheet = Image.new('RGB', (1512, 860), '#F5F1EB')
    pen = ImageDraw.Draw(sheet)
    pen.text((56, 40), '纸间 / 新增三组配色', font=load_review_font(32), fill='#25211E')
    pen.text((56, 98), '保持 C 的艺术构图，比较三组颜色本身的视觉强度。', font=load_review_font(19), fill='#625B55')
    for index, palette in enumerate(['violet', 'pine', 'klein']):
        x = 56+index*488
        icon = render_experimental_icon(palette)
        paste_icon(sheet, icon, (x, 168), 424)
        paper, ink, title = PALETTES[palette]
        pen.text((x, 626), title, font=load_review_font(26), fill='#25211E')
        pen.text((x, 671), f'{paper} / {ink}', font=load_review_font(19), fill='#625B55')
        paste_icon(sheet, icon, (x, 724), 60)
        paste_icon(sheet, icon, (x+84, 736), 40)
        icon.save(REVIEW/f'ICON-ADDED-{palette}.png', optimize=True)
    path = REVIEW/'ICON-ADDED-PALETTES.png'
    sheet.save(path, optimize=True)
    return {'preview': str(path)}


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--added-palettes', action='store_true')
    options = parser.parse_args()
    print(json.dumps(render_added_palettes() if options.added_palettes else render_contrast_study(), ensure_ascii=False))
