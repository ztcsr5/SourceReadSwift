"""Extract the current commit's native comic evidence without hiding failures.
Usage: python -X utf8 scripts/release117_comic_report.py
"""
from pathlib import Path
import base64,collections,hashlib,json,re,subprocess
ROOT=Path(__file__).resolve().parents[1];OUT=Path('F:/SourceReadSwift/release-1.1.7')
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
status=json.loads((OUT/'ci-status.json').read_text(encoding='utf-8'));assert status['head']==head
run=next(r for r in status['runs'] if r['name']=='iOS')
job=next(j for j in run['jobs'] if j['name']=='build');log=OUT/f"job-{job['id']}.log"
text=log.read_text(encoding='utf-8',errors='replace')
rows={}
malformed=[]
for value in re.findall(r'COMIC_ROW_B64 ([A-Za-z0-9+/]+={0,2})',text):
    try:row=json.loads(base64.b64decode(value));rows[row['index']]=row
    except (ValueError,json.JSONDecodeError):malformed.append({'encoded_length':len(value),'prefix':value[:20],'suffix':value[-20:]})
if malformed:print('INCOMPLETE_LOG_RECORDS',json.dumps(malformed))
assert set(rows)==set(range(31)),len(rows)
report={'head':head,'run':run['id'],'job':job['id'],'log_sha256':hashlib.sha256(log.read_bytes()).hexdigest(),
        'scope':'31 original type2 configurations; first chapter only; sample first/middle/last pages, not all books/pages.',
        'total':31,'first_image_decoded':sum(r['decoded'] for r in rows.values()),
        'all_sampled_images_decoded':sum(bool(r.get('sampledDecoded')) and all(r['sampledDecoded']) for r in rows.values()),
        'failure_kinds':dict(collections.Counter(r.get('failureKind','old-probe') for r in rows.values() if r.get('failureKind','old-probe'))),
        'rows':[rows[i] for i in range(31)]}
target=OUT/'closeout34'/head;target.mkdir(parents=True,exist_ok=True)
(target/'comic-pipeline-31.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in report.items() if k!='rows'},ensure_ascii=False,indent=2))
for r in report['rows']:print(json.dumps({k:r.get(k) for k in ['index','name','stage','failureKind','sampledPositions','sampledDecoded','message']},ensure_ascii=False))
