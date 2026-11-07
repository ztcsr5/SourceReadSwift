"""Render editable two-colour brand directions and the selected opaque iOS icon.

Usage: python -B -X utf8 scripts/generate_master_app_icon.py --preview
       python -B -X utf8 scripts/generate_master_app_icon.py --design fold --palette periwinkle
Uses the existing Pillow toolchain, with no network/image API calls.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'SourceReadSwift/App/Assets.xcassets'
REVIEW = ROOT / 'docs/project-audit-20261108'
PALETTES = {
    'periwinkle': ('#7B88D7', '#6D483B', '长春花蓝 × 可可棕'),
    'blush': ('#FF7CA2', '#000000', '胭脂粉 × 墨黑'),
    'berry': ('#65020A', '#18D5E7', '浆果红 × 湖蓝'),
    'peach': ('#FACBC6', '#465C47', '裸桃粉 × 苔青'),
    'violet': ('#0B0C10', '#A855F7', '墨黑 × 星紫'),
    'pine': ('#3A6341', '#E8E8E4', '松针绿 × 雾灰白'),
    'klein': ('#012696', '#A4E2C6', '克莱因蓝 × 艾绿'),
}
DESIGNS = {'fold': ('01 / 折序', '流动的折面 · 清晰的负形'),
           'wing': ('02 / 栖羽', '舒展的羽翼 · 轻盈的动势'),
           'portal': ('03 / 间隙', '建筑式拱门 · 安静的秩序'),
           'swallow': ('04 / 飞白', '斜向展开 · 锐利与圆润'),
           'current': ('05 / 流转', '连续曲线 · 自然的节奏'),
           'petal': ('06 / 花信', '四瓣旋转 · 留白成形')}
SCALE = 3
EDGE = 1024 * SCALE


def bezier_shape(commands: list) -> list:
    """Flatten cubic paths while preserving editable control points."""
    points = []
    current = (0, 0)
    for command in commands:
        if command[0] in ('M', 'L'):
            current = tuple(command[1:])
            points.append(current)
        elif command[0] == 'C':
            start = current
            control_a, control_b, end = command[1:3], command[3:5], command[5:7]
            for step in range(1, 81):
                t = step / 80
                points.append(tuple((1-t)**3*start[k] + 3*(1-t)**2*t*control_a[k]
                                    + 3*(1-t)*t*t*control_b[k] + t**3*end[k] for k in (0, 1)))
            current = tuple(end)
    return [(x*SCALE, y*SCALE) for x, y in points]


def draw_fold(pen: ImageDraw.ImageDraw, ink: str, paper: str) -> None:
    """Two opposing folded strokes share a diagonal counterspace."""
    upper = [('M', 258, 273), ('C', 274, 235, 311, 218, 357, 218), ('L', 781, 218),
             ('C', 750, 316, 702, 375, 606, 419), ('L', 394, 516),
             ('C', 329, 546, 284, 586, 252, 641), ('L', 252, 396),
             ('C', 252, 338, 247, 301, 258, 273)]
    lower = [('M', 766, 751), ('C', 750, 789, 713, 806, 667, 806), ('L', 243, 806),
             ('C', 274, 708, 322, 649, 418, 605), ('L', 630, 508),
             ('C', 695, 478, 740, 438, 772, 383), ('L', 772, 628),
             ('C', 772, 686, 777, 723, 766, 751)]
    for commands in (upper, lower):
        pen.polygon(bezier_shape(commands), fill=ink)


def draw_wing(pen: ImageDraw.ImageDraw, ink: str, paper: str) -> None:
    """A broad silhouette opens into three tapered feathers."""
    commands = [('M', 223, 744), ('C', 237, 575, 310, 404, 446, 294),
                ('C', 568, 196, 705, 192, 813, 211),
                ('C', 778, 366, 663, 456, 518, 466),
                ('C', 616, 486, 695, 469, 762, 431),
                ('C', 710, 570, 601, 628, 461, 603),
                ('C', 525, 647, 609, 653, 681, 637),
                ('C', 591, 760, 458, 773, 350, 714),
                ('C', 315, 719, 272, 732, 223, 744)]
    pen.polygon(bezier_shape(commands), fill=ink)


def draw_portal(pen: ImageDraw.ImageDraw, ink: str, paper: str) -> None:
    """An arch and offset aperture create an architectural monogram."""
    outer = [('M', 237, 787), ('L', 237, 460), ('C', 237, 280, 345, 205, 508, 205),
             ('C', 671, 205, 787, 280, 787, 460), ('L', 787, 787), ('L', 644, 787),
             ('L', 644, 465), ('C', 644, 375, 596, 334, 512, 334),
             ('C', 428, 334, 380, 375, 380, 465), ('L', 380, 787)]
    pen.polygon(bezier_shape(outer), fill=ink)
    inner = [('M', 456, 787), ('L', 456, 509), ('C', 456, 472, 477, 450, 512, 450),
             ('C', 547, 450, 568, 472, 568, 509), ('L', 568, 711),
             ('C', 568, 753, 523, 787, 456, 787)]
    pen.polygon(bezier_shape(inner), fill=ink)


def draw_swallow(pen: ImageDraw.ImageDraw, ink: str, paper: str) -> None:
    """An ascending abstract swallow balances a sharp tip against broad curved wings."""
    commands = [('M', 211, 480), ('C', 369, 485, 514, 376, 687, 201),
                ('C', 679, 336, 648, 430, 589, 493), ('L', 823, 412),
                ('C', 742, 536, 645, 632, 514, 651),
                ('C', 421, 665, 353, 711, 286, 806), ('L', 327, 606),
                ('C', 296, 582, 252, 529, 211, 480)]
    pen.polygon(bezier_shape(commands), fill=ink)


def draw_current(pen: ImageDraw.ImageDraw, ink: str, paper: str) -> None:
    """Three broad curved strokes move as a single asymmetric emblem."""
    strokes = [
        [('M', 233, 420), ('C', 355, 232, 533, 190, 753, 248),
         ('C', 691, 372, 600, 435, 465, 427), ('C', 374, 422, 297, 410, 233, 420)],
        [('M', 216, 572), ('C', 334, 460, 418, 482, 539, 487),
         ('C', 655, 490, 725, 445, 798, 385), ('C', 785, 562, 658, 645, 520, 621),
         ('C', 397, 600, 322, 558, 216, 572)],
        [('M', 239, 725), ('C', 342, 633, 419, 659, 523, 680),
         ('C', 612, 701, 691, 690, 751, 654), ('C', 671, 804, 470, 855, 239, 725)],
    ]
    for stroke in strokes:
        pen.polygon(bezier_shape(stroke), fill=ink)


def draw_petal(pen: ImageDraw.ImageDraw, ink: str, paper: str) -> None:
    """Four curved lobes leave a small diamond of negative space, with no centre dot."""
    petal = [('M', 478, 460), ('C', 339, 452, 231, 371, 232, 253),
             ('C', 232, 227, 246, 211, 270, 214),
             ('C', 392, 227, 470, 324, 478, 460)]
    vertices = bezier_shape(petal)
    centre = 512*SCALE
    for _ in range(4):
        pen.polygon(vertices, fill=ink)
        vertices = [(2*centre-y, x) for x, y in vertices]


def render_icon(design: str, palette: str) -> Image.Image:
    """Export two solid colours with antialiased edges and no baked corner mask."""
    paper, ink, _ = PALETTES[palette]
    canvas = Image.new('RGB', (EDGE, EDGE), paper)
    drawers = {'fold': draw_fold, 'wing': draw_wing, 'portal': draw_portal,
               'swallow': draw_swallow, 'current': draw_current, 'petal': draw_petal}
    drawers[design](ImageDraw.Draw(canvas), ink, paper)
    return canvas.resize((1024, 1024), Image.Resampling.LANCZOS)


def load_review_font(size: int) -> ImageFont.FreeTypeFont:
    """Use a local CJK font only on the presentation board."""
    candidates = [Path('C:/Windows/Fonts/msyh.ttc'), Path('/System/Library/Fonts/PingFang.ttc')]
    available = next((path for path in candidates if path.exists()), None)
    return ImageFont.truetype(str(available), size) if available else ImageFont.load_default(size=size)


def paste_icon(sheet: Image.Image, icon: Image.Image, position: tuple, size: int) -> None:
    """Simulate system cropping only on presentation boards."""
    crop = Image.new('L', (size, size))
    ImageDraw.Draw(crop).rounded_rectangle((0, 0, size-1, size-1), radius=size*.225, fill=255)
    sheet.paste(icon.resize((size, size), Image.Resampling.LANCZOS), position, crop)


def render_directions() -> Path:
    """Show three silhouettes and four strictly paired reference palettes."""
    REVIEW.mkdir(exist_ok=True)
    sheet = Image.new('RGB', (1440, 1230), '#F5F1EB')
    pen = ImageDraw.Draw(sheet)
    pen.text((64, 44), '纸间 / 双 色 图 标', font=load_review_font(34), fill='#25211E')
    pen.text((64, 100), '三种轮廓，同一组长春花蓝与可可棕。下方比较四组参考配色。', font=load_review_font(19), fill='#625B55')
    for index, design in enumerate(['fold', 'wing', 'portal']):
        title, caption = DESIGNS[design]
        x = 64 + index*453
        icon = render_icon(design, 'periwinkle')
        paste_icon(sheet, icon, (x, 164), 390)
        pen.text((x, 580), title, font=load_review_font(27), fill='#25211E')
        pen.text((x, 627), caption, font=load_review_font(18), fill='#625B55')
        paste_icon(sheet, icon, (x, 675), 64)
        paste_icon(sheet, icon, (x+88, 687), 40)
        pen.text((x+150, 692), '64 / 40 px', font=load_review_font(16), fill='#625B55')
    pen.line((64, 785, 1376, 785), fill='#D6CFC5', width=1)
    for index, palette in enumerate(['periwinkle', 'blush', 'berry', 'peach']):
        paper, ink, title = PALETTES[palette]
        x = 64 + index*343
        paste_icon(sheet, render_icon('fold', palette), (x, 825), 220)
        pen.text((x, 1074), title, font=load_review_font(19), fill='#25211E')
        pen.text((x, 1111), f'{paper}  /  {ink}', font=load_review_font(16), fill='#625B55')
    path = REVIEW/'ICON-DIRECTIONS.png'
    sheet.save(path, optimize=True)
    return path


def render_second_directions() -> Path:
    """Keep the selected fold beside three new silhouettes in both preferred palettes."""
    sheet = Image.new('RGB', (1536, 1190), '#F5F1EB')
    pen = ImageDraw.Draw(sheet)
    pen.text((56, 40), '纸间 / 保留折序，再看三种轮廓', font=load_review_font(32), fill='#25211E')
    pen.text((56, 99), '上排：浆果红 × 湖蓝     下排：裸桃粉 × 苔青', font=load_review_font(20), fill='#625B55')
    for index, design in enumerate(['fold', 'swallow', 'current', 'petal']):
        x = 56+index*371
        for y, palette in [(162, 'berry'), (642, 'peach')]:
            icon = render_icon(design, palette)
            paste_icon(sheet, icon, (x, y), 310)
            paste_icon(sheet, icon, (x+200, y+341), 44)
            pen.text((x, y+340), DESIGNS[design][0], font=load_review_font(24), fill='#25211E')
            pen.text((x, y+390), DESIGNS[design][1], font=load_review_font(16), fill='#625B55')
    path = REVIEW/'ICON-DIRECTIONS-02.png'
    sheet.save(path, optimize=True)
    return path


def render_material_icon(palette: str) -> Image.Image:
    """Light a shallow, bevelled emblem using its measured silhouette, not a drop-shadow preset."""
    import cv2
    import numpy as np
    from PIL import ImageColor
    mask_canvas = Image.new('RGB', (EDGE, EDGE), 'black')
    draw_fold(ImageDraw.Draw(mask_canvas), 'white', 'black')
    mask = np.asarray(mask_canvas.resize((1024, 1024), Image.Resampling.LANCZOS).convert('L'))/255.0
    distance = cv2.distanceTransform((mask > .5).astype('uint8'), cv2.DIST_L2, 5)
    bevel = np.clip(distance/25.0, 0, 1)
    height = 25.0*np.sqrt(1-(1-bevel)**2)
    height = cv2.GaussianBlur(height, (0, 0), 1.2)
    slope_y, slope_x = np.gradient(height)
    normals = np.stack([-slope_x, -slope_y, np.ones_like(height)], axis=-1)
    normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
    light = np.array([-.48, -.62, .78])
    light /= np.linalg.norm(light)
    halfway = light + np.array([0, 0, 1])
    halfway /= np.linalg.norm(halfway)
    diffuse = np.maximum(0, np.sum(normals*light, axis=-1))
    specular = np.maximum(0, np.sum(normals*halfway, axis=-1))**35
    y, x = np.mgrid[:1024, :1024]/1024.0
    paper, ink, _ = PALETTES[palette]
    base = np.array(ImageColor.getrgb(paper))/255.0
    pigment = np.array(ImageColor.getrgb(ink))/255.0
    glow = np.exp(-((x-.25)**2+(y-.12)**2)/.48)
    ground = np.ones((1024, 1024, 3))*base*(.86+.15*glow[..., None])
    shifted = np.zeros_like(mask)
    shifted[18:, 8:] = mask[:-18, :-8]
    shadow = cv2.GaussianBlur(shifted, (0, 0), 14)
    contact = cv2.GaussianBlur(shifted, (0, 0), 3)
    ground *= (1-.32*shadow-.12*contact)[..., None]
    face = pigment*(.62+.43*diffuse[..., None])
    face += .16*specular[..., None]*np.array([.78, .90, .94])
    face *= (.97+.07*(1-x-y/3))[..., None]
    grain = np.random.default_rng(42).normal(0, .0015, mask.shape)
    composed = ground*(1-mask[..., None])+face*mask[..., None]+grain[..., None]
    return Image.fromarray(np.uint8(np.clip(composed, 0, 1)*255), 'RGB')


def render_refined_flat_icon(palette: str) -> Image.Image:
    """Condense the emblem and give its countershape room inside a quiet colour field."""
    paper, ink, _ = PALETTES[palette]
    mask = Image.new('RGB', (EDGE, EDGE), 'black')
    draw_fold(ImageDraw.Draw(mask), 'white', 'black')
    mask = mask.convert('L').resize((860, 1080), Image.Resampling.LANCZOS)
    canvas = Image.new('RGB', (1024, 1024), paper)
    canvas.paste(ink, (82, -28), mask)
    return canvas


def render_experimental_icon(palette: str) -> Image.Image:
    """An enlarged cropped glyph changes polarity across a curved colour division."""
    import numpy as np
    from PIL import ImageColor
    paper, ink, _ = PALETTES[palette]
    shape = Image.new('RGB', (EDGE, EDGE), 'black')
    draw_fold(ImageDraw.Draw(shape), 'white', 'black')
    shape = shape.convert('L').resize((1434, 1434), Image.Resampling.LANCZOS)
    shape = shape.rotate(-14, resample=Image.Resampling.BICUBIC)
    shape = shape.crop((205, 205, 1229, 1229))
    glyph = np.asarray(shape)/255.0
    y, x = np.mgrid[:1024, :1024]
    division = 480+120*np.sin((x-190)/800*np.pi)
    field = np.clip((y-division)/2+0.5, 0, 1)
    mix = glyph*(1-field)+(1-glyph)*field
    first = np.array(ImageColor.getrgb(paper))
    second = np.array(ImageColor.getrgb(ink))
    canvas = first*(1-mix[..., None])+second*mix[..., None]
    return Image.fromarray(np.uint8(canvas), 'RGB')


def render_interlaced_icon(palette: str) -> Image.Image:
    """Keep the complete mark inset, with depth confined to its central crossing."""
    import numpy as np
    from PIL import ImageColor
    paper, ink, _ = PALETTES[palette]
    shape = Image.new('RGB', (EDGE, EDGE), 'black')
    draw_fold(ImageDraw.Draw(shape), 'white', 'black')
    shape = shape.convert('L').resize((1126, 1126), Image.Resampling.LANCZOS)
    shape = shape.rotate(-14, resample=Image.Resampling.BICUBIC)
    shape = shape.crop((51, 51, 1075, 1075))
    glyph = np.asarray(shape)/255.0
    y, x = np.mgrid[:1024, :1024]
    boundary = 480+120*np.sin((x-190)/800*np.pi)
    field = np.clip((y-boundary)/2+.5, 0, 1)
    mix = glyph*(1-field)+(1-glyph)*field
    first, second = np.array(ImageColor.getrgb(paper)), np.array(ImageColor.getrgb(ink))
    rgb = first*(1-mix[..., None])+second*mix[..., None]
    # Local occlusion at the crossing; the background and outer silhouette stay flat.
    # Stop at four falloff lengths: an infinite tail darkens flat pixels after uint8 conversion.
    distance = np.maximum(y-boundary, 0)
    falloff = np.maximum(np.exp(-distance/16)-np.exp(-4), 0)/(1-np.exp(-4))
    falloff *= (y >= boundary)
    crossing = glyph*np.clip((x-165)/70,0,1)*np.clip((860-x)/70,0,1)
    rgb *= (1-.15*falloff*crossing)[...,None]
    return Image.fromarray(np.uint8(np.clip(rgb,0,255)), 'RGB')


def render_style_directions() -> Path:
    """Compare material, restrained flat geometry and graphic experimentation in two palettes."""
    sheet = Image.new('RGB', (1536, 1430), '#F5F1EB')
    pen = ImageDraw.Draw(sheet)
    pen.text((60, 44), '纸间 / 三种设计语言', font=load_review_font(34), fill='#25211E')
    pen.text((60, 103), '相同双色，比较材质、比例与图形表达。小图为 48 px。', font=load_review_font(20), fill='#625B55')
    styles = [(render_material_icon, 'A / 雕塑质感', '浅浮雕、圆润切面、细哑光'),
              (render_refined_flat_icon, 'B / 平面奢简', '收窄比例、垂直张力、大留白'),
              (render_experimental_icon, 'C / 艺术实验', '放大裁切、曲线分界、双色反转')]
    for column, (renderer, title, caption) in enumerate(styles):
        x = 60+column*500
        pen.text((x, 165), title, font=load_review_font(27), fill='#25211E')
        pen.text((x, 210), caption, font=load_review_font(18), fill='#625B55')
        for y, palette in [(262, 'berry'), (827, 'peach')]:
            icon = renderer(palette)
            paste_icon(sheet, icon, (x, y), 416)
            paste_icon(sheet, icon, (x, y+442), 48)
            pen.text((x+72, y+450), PALETTES[palette][2], font=load_review_font(18), fill='#625B55')
            icon.save(REVIEW/f'ICON-STYLE-{column+1}-{palette}.png', optimize=True)
    path = REVIEW/'ICON-STYLES.png'
    sheet.save(path, optimize=True)
    return path


def create_master_app_icon(design: str, palette: str, style: str = 'interlaced') -> dict:
    """Write the selected opaque icon and matching in-app asset."""
    icon = render_interlaced_icon(palette) if style == 'interlaced' else render_icon(design, palette)
    path = ASSETS/'AppIcon.appiconset/AppIcon-1024.png'
    icon.save(path, optimize=True)
    brand = ASSETS/'BrandMark.imageset'
    brand.mkdir(exist_ok=True)
    icon.resize((192, 192), Image.Resampling.LANCZOS).save(brand/'BrandMark.png', optimize=True)
    (brand/'Contents.json').write_text(json.dumps({'images': [{'filename': 'BrandMark.png', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1}}, indent=2)+'\n', encoding='utf8')
    sheet = Image.new('RGB', (1060, 700), '#F5F1EB')
    paste_icon(sheet, icon, (40, 40), 600)
    pen = ImageDraw.Draw(sheet)
    title = '折序 / 交错微立体' if style == 'interlaced' else DESIGNS[design][0]
    pen.text((700, 48), title, font=load_review_font(25), fill='#25211E')
    for x, size in [(700, 120), (860, 60), (960, 40)]:
        paste_icon(sheet, icon, (x, 130), size)
        pen.text((x, 276), f'{size} px', font=load_review_font(15), fill='#625B55')
    for index, colour in enumerate(PALETTES[palette][:2]):
        y = 360+index*90
        pen.rounded_rectangle((700, y, 748, y+48), radius=12, fill=colour)
        pen.text((772, y+12), colour, font=load_review_font(21), fill='#25211E')
    pen.text((700, 560), PALETTES[palette][2], font=load_review_font(22), fill='#25211E')
    REVIEW.mkdir(exist_ok=True)
    sheet.save(REVIEW/'ICON-REVIEW.png', optimize=True)
    return {'icon': str(path), 'bytes': path.stat().st_size, 'mode': icon.mode,
            'size': icon.size, 'design': design, 'style': style, 'palette': PALETTES[palette]}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', action='store_true')
    parser.add_argument('--more', action='store_true')
    parser.add_argument('--styles', action='store_true')
    parser.add_argument('--design', choices=DESIGNS, default='fold')
    parser.add_argument('--palette', choices=PALETTES, default='pine')
    parser.add_argument('--style', choices=['interlaced', 'flat'], default='interlaced')
    options = parser.parse_args()
    if options.styles:
        result = {'preview': str(render_style_directions())}
    elif options.more:
        result = {'preview': str(render_second_directions())}
    else:
        result = {'preview': str(render_directions())} if options.preview else create_master_app_icon(options.design, options.palette, options.style)
    print(json.dumps(result, ensure_ascii=False))
