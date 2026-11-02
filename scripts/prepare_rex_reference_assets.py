"""Copy unmodified UI-reference artwork from the user-authorized IPA, not code.

Usage: python -X utf8 scripts/prepare_rex_reference_assets.py
Private visual study only. No executable, shader, entitlement, or credential is copied.
"""
from pathlib import Path
import hashlib
import json
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LAB = ROOT / 'experiments/ZhijianMotionLab'
IPA = Path('D:/QQ游戏/Rex.1.0.2(b4).ipa')
IDS = [106379, 157336, 82728, 496243, 508943, 87739, 560057, 475557,
       603, 240, 60573, 12971, 277834, 823219, 10997, 110356, 71712,
       46298, 799876, 39852, 1416, 238, 10376]


def main() -> None:
    records = []
    catalog = []
    with zipfile.ZipFile(IPA) as archive:
        names = archive.namelist()
        source = json.loads(archive.read(next(n for n in names if n.endswith('ShowcaseMediaLibrary.json'))))
        by_id = {i['tmdbID']: i for i in source['items']}
        for identifier in IDS:
            item = by_id[identifier]
            assets = {'poster': ('Ref' + str(identifier), item['localPosterName'] + '.jpg')}
            for field, prefix in [('backdropPath', 'RefBack'), ('logoPath', 'RefTitle')]:
                if item.get(field):
                    assets[field] = (prefix + str(identifier), 'showcase-art-' + item[field].lstrip('/'))
            found = {}
            for field, (asset, filename) in assets.items():
                entry = next((n for n in names if '/RexDesign_RexDesign.bundle/' in n and n.endswith('/' + filename)), None)
                if entry is None:
                    continue
                content = archive.read(entry)
                folder = LAB / 'Sources/Assets.xcassets' / (asset + '.imageset')
                folder.mkdir(parents=True, exist_ok=True)
                (folder / filename).write_bytes(content)
                (folder / 'Contents.json').write_text(json.dumps({'images': [{'filename': filename, 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')
                found[field] = asset
                records.append({'asset': asset, 'entry': entry, 'bytes': len(content), 'sha256': hashlib.sha256(content).hexdigest()})
            catalog.append({'id': identifier, 'title': item['title'], 'poster': found['poster'],
                            'backdrop': found.get('backdropPath', found['poster']),
                            'logo': found.get('logoPath', ''), 'year': item['releaseDate'][:4],
                            'release': item['releaseDate'], 'genre': ' '.join(item['genres'][:2]),
                            'overview': item['overview'][:360], 'rating': f"{item['rating']:.1f}"})
    (LAB / 'Sources/ReferenceMedia.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    (LAB / 'docs/REFERENCE-ASSETS.json').write_text(json.dumps({'purpose': 'Private comparison against user-provided REX video; not redistribution clearance.', 'ipa_sha256': hashlib.sha256(IPA.read_bytes()).hexdigest(), 'attribution': source['attribution'], 'assets': records}, ensure_ascii=False, indent=2) + '\n', encoding='utf8')
    print(f'Copied {len(records)} unmodified reference assets for {len(catalog)} titles; no binary or runtime copied.')


if __name__ == '__main__':
    main()
