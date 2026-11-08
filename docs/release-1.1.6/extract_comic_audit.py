from pathlib import Path
import base64, collections, csv, hashlib, io, json, re, shutil
import ci

O, H = ci.OUT, ci.ci.HEAD
status = json.loads((O/'ci-status.json').read_text(encoding='utf8'))
assert status['head'] == H
run = next(r for r in status['runs'] if r['name'] == 'iOS')
job = next(j for j in run['jobs'] if j['name'] == 'build')
logfile = O / f"job-{job['id']}.log"
if not logfile.exists():
    logfile.write_bytes(ci.ci.signed_download(f"actions/jobs/{job['id']}/logs"))
log = logfile.read_text(encoding='utf8', errors='replace')
rows = {}
for encoded in re.findall(r'COMIC_ROW_B64 ([A-Za-z0-9+/=]+)', log):
    row = json.loads(base64.b64decode(encoded))
    rows[row['index']] = row
assert set(rows) == set(range(31)), sorted(rows)
rows = [rows[i] for i in range(31)]
source_path = Path('D:/QQ游戏/all_book_sources.json')
source_sha = hashlib.sha256(source_path.read_bytes()).hexdigest()
report = {'head': H, 'input_sha256': source_sha, 'run': run['html_url'],
          'scope': 'All 31 type=2 source configurations; author checkKeyWord or fallback 斗罗; first search result, first chapter, first image only. No login/purchase. Not all books/chapters, not all 997 sources live-tested.',
          'total': len(rows), 'decoded': sum(r['decoded'] for r in rows),
          'stages': dict(collections.Counter(r['stage'] for r in rows)), 'rows': rows}
out = O/'source-audit'
previous = out/'comic-pipeline-31.json'
if previous.exists():
    old_head = json.loads(previous.read_text(encoding='utf8'))['head']
    if old_head != H:
        archive = out/'runs'/old_head
        archive.mkdir(parents=True,exist_ok=True)
        for suffix in ['json','csv']:
            old = out/f'comic-pipeline-31.{suffix}'
            if old.exists(): shutil.copyfile(old,archive/old.name)
(out/'comic-pipeline-31.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf8')
fields = ['index','name','keyword','stage','searchCount','chapterCount','chapterTitle','contentPreview','firstImageURL','imageCount','decoded','elapsedSeconds','message']
with (out/'comic-pipeline-31.csv').open('w',encoding='utf-8-sig', newline='') as f:
    writer = csv.DictWriter(f,fieldnames=fields); writer.writeheader(); writer.writerows(rows)
print(json.dumps({k:v for k,v in report.items() if k != 'rows'}, ensure_ascii=False, indent=2))
for row in rows:
    print(json.dumps(row,ensure_ascii=False))
