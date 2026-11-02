"""Fetch seven explicitly selected book covers for the private offline reading test.

Usage: python -X utf8 scripts/prepare_reading_lab_covers.py
Uses the documented Open Library Covers API, not crawling/search or an app gateway.
Existing cover files are reused; unmodified bytes and attribution are recorded.
"""
from pathlib import Path
import hashlib
import io
import json
import time
import urllib.request
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'experiments/ZhijianMotionLab'
SELECTED = [
    ('BookThreeBody', '9787536692930', 10246665, '三体'),
    ('BookDune', '9780441172719', 15166231, '沙丘'),
    ('BookPrince', '9780156012195', 115508, '小王子'),
    ('BookHobbit', '9780547928227', 12003329, '霍比特人'),
    ('BookPotter', '9780439708180', 14656855, '哈利·波特与魔法石'),
    ('Book1984', '9780451524935', 15257377, '1984'),
    ('BookHitchhiker', '9780345391803', 8774325, '银河系漫游指南'),
]


def main() -> None:
    covers = []
    for asset, isbn, identifier, title in SELECTED:
        folder = LAB / 'Sources/Assets.xcassets' / (asset + '.imageset')
        folder.mkdir(parents=True, exist_ok=True)
        target = folder / (asset + '.jpg')
        source = f'https://covers.openlibrary.org/b/id/{identifier}-L.jpg?default=false'
        if not target.exists():
            request = urllib.request.Request(source, headers={'User-Agent': 'Zhijian-private-UI-test/0.1'})
            with urllib.request.urlopen(request, timeout=40) as response:
                if response.headers.get_content_type() not in ['image/jpeg', 'image/png']:
                    raise ValueError(f'Expected image bytes for {title}')
                content = response.read(8_000_001)
            if len(content) > 8_000_000:
                raise ValueError(f'Cover exceeds the size limit for {title}')
            image = Image.open(io.BytesIO(content)); image.verify()
            target.write_bytes(content)
            time.sleep(0.5)
        content = target.read_bytes()
        with Image.open(target) as image:
            dimensions = image.size
            if min(dimensions) < 150 or max(dimensions) > 4096:
                raise ValueError(f'Cover dimensions unsuitable for {title}: {dimensions}')
        (folder / 'Contents.json').write_text(json.dumps({'images': [{'filename': target.name, 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
        covers.append({'title': title, 'asset': asset, 'isbn': isbn, 'cover_id': identifier, 'source': source, 'credit': f'https://openlibrary.org/isbn/{isbn}', 'bytes': len(content), 'dimensions': dimensions, 'sha256': hashlib.sha256(content).hexdigest()})
        print(title, dimensions, len(content), flush=True)
    (LAB / 'docs/BOOK-COVERS.json').write_text(json.dumps({'purpose': 'Seven hand-selected, unmodified publisher book covers for a private offline UI experiment; not a redistribution license.', 'api_documentation': 'https://openlibrary.org/dev/docs/api/covers', 'covers': covers}, ensure_ascii=False, indent=2) + '\n', encoding='utf8')


if __name__ == '__main__':
    main()
