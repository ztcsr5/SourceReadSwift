from pathlib import Path
import json, shutil, sys
from PIL import Image, ImageDraw
import ci

folder = ci.OUT / 'native-evidence' / ci.ci.HEAD
all_images = []
for runtime in (sys.argv[1:] or ['ios18-ui', 'ios26-ui']):
    root = folder / runtime
    manifest = json.loads((root / 'manifest.json').read_text(encoding='utf8'))
    images = {}
    for test in manifest:
        for attachment in test['attachments']:
            source = root / attachment['exportedFileName']
            if source.suffix.lower() not in ['.png', '.jpg', '.jpeg']: continue
            name = attachment['suggestedHumanReadableName'].split('_0_')[0]
            dest = root / 'named' / (name + source.suffix)
            dest.parent.mkdir(exist_ok=True)
            shutil.copyfile(source, dest)
            images[name] = dest
            all_images.append({'runtime': runtime, 'name': name, 'path': str(source), 'named': str(dest)})

    def sheet(names, output, columns=5, cell=(256, 340)):
        canvas = Image.new('RGB', (columns * cell[0], ((len(names)+columns-1)//columns) * cell[1]), '#dddddd')
        draw = ImageDraw.Draw(canvas)
        for i, name in enumerate(names):
            x, y = (i % columns) * cell[0], (i // columns) * cell[1]
            draw.text((x + 4, y + 3), name.replace('release116-', '').replace('density-', ''), fill='black')
            im = Image.open(images[name]).convert('RGB')
            im.thumbnail((cell[0]-8, cell[1]-28))
            canvas.paste(im, (x + (cell[0]-im.width)//2, y+24))
        canvas.save(folder / f'{runtime}-{output}.jpg', quality=88, optimize=True)

    themes = sorted(n for n in images if n.startswith('release116-theme-'))
    assert len(themes) == 12, (runtime, list(images))
    sheet(themes, 'themes', columns=6, cell=(212, 368))
    reader = sorted(n for n in images if n.startswith('release116-reader-'))
    legacy = [n for n in images if n.startswith('release116-legacy-')]
    assert len(reader) == 2 and len(legacy) == 1, (runtime, images.keys())
    sheet(reader + legacy, 'reader-and-navigation', columns=3, cell=(390, 880))
    old = sorted(n for n in images if n.startswith('density-'))
    assert len(old) == 10, (runtime, old)
    sheet(old, 'regression', columns=5, cell=(256, 430))
(folder / 'screen-index.json').write_text(json.dumps(all_images, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps({'head': ci.ci.HEAD, 'screens': len(all_images), 'folder': str(folder)}, ensure_ascii=False))
