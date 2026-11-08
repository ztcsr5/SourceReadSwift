"""Preserve a completed compatibility CI checkpoint before the next commit.
Usage: python -X utf8 scripts/release117_save_closeout_checkpoint.py
"""
from pathlib import Path
import json,subprocess,shutil,re,hashlib
ROOT=Path(__file__).resolve().parents[1];OUT=Path('F:/SourceReadSwift/release-1.1.7')
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
status=json.loads((OUT/'ci-status.json').read_text(encoding='utf-8'))
assert status['head']==head and len(status['runs'])==2 and all(r['status']=='completed' and r['conclusion']=='success' for r in status['runs'])
shutil.copy2(OUT/'ci-status.json',OUT/f'ci-{head[:7]}.json')
jobs=[]
for run in status['runs']:
    for job in run['jobs']:
        path=OUT/f"job-{job['id']}.log";text=path.read_text(encoding='utf-8',errors='replace')
        counts=re.findall(r'Executed (\d+) tests, with (?:(\d+) tests skipped and )?(\d+) failures',text)
        jobs.append({'run':run['id'],'job':job['id'],'status':job['conclusion'],'counts':counts[-1] if counts else None,'log_sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
report={'head':head,'state':'Compatibility checkpoint only, items3/4 not all remote sources fixed; 11/12 pending, 17-20 held.',
        'jobs':jobs,'comic_report':str(OUT/'closeout34'/head/'comic-pipeline-31.json')}
(OUT/'closeout34'/head/'CHECKPOINT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False,indent=2))
