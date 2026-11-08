from pathlib import Path
import base64, collections, hashlib, json, re

out = Path('F:/SourceReadSwift/release-1.1.7')
status = json.loads((out/'ci-559b5a3.json').read_text(encoding='utf8'))
run = next(r for r in status['runs'] if r['name'] == 'iOS')
job = next(j for j in run['jobs'] if j['name'] == 'build')
log = (out/f"job-{job['id']}.log").read_text(encoding='utf8', errors='replace')
rows = {}
for encoded in re.findall(r'COMIC_ROW_B64 ([A-Za-z0-9+/=]+)', log):
    row = json.loads(base64.b64decode(encoded)); rows[row['index']] = row
assert set(rows) == set(range(31)), sorted(rows)
rows = [rows[i] for i in range(31)]
report = {'head': status['head'], 'run': run['html_url'],
          'input_sha256': hashlib.sha256(Path('D:/QQ游戏/all_book_sources.json').read_bytes()).hexdigest(),
          'scope': '31 type=2 original configurations; author keyword/fallback, first result, first chapter, first image decode only. Not all books, not all997 sources live tested.',
          'total': len(rows), 'decoded': sum(r['decoded'] for r in rows),
          'stages': dict(collections.Counter(r['stage'] for r in rows)), 'rows': rows}
folder = out/'source-audit'/status['head']; folder.mkdir(parents=True, exist_ok=True)
(folder/'comic-pipeline-31.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k != 'rows'}, ensure_ascii=False, indent=2))
print(json.dumps([{'name': r['name'], 'stage': r['stage'], 'decoded': r['decoded'], 'message': r.get('message')} for r in rows], ensure_ascii=False))
