"""Bounded public endpoint probes, not a claim of end-to-end comic success."""
from pathlib import Path
import concurrent.futures, collections, hashlib, json, time, urllib.parse
import requests
O=Path('F:/SourceReadSwift/release-1.1.6/source-audit')
sources=json.loads((O/'comic-sources.json').read_text(encoding='utf8'))
def probe(s):
    name=s.get('bookSourceName','');url=s.get('bookSourceUrl','').split('##')[0].strip()
    row={'name':name,'base':url,'enginePipeline':'NOT RUN','imageDisplay':'NOT RUN'}
    if urllib.parse.urlsplit(url).scheme not in ('http','https'):
        return row|{'transport':'invalid-base'}
    start=time.monotonic()
    try:
        # Never send imported cookies, login credentials or execute JS here.
        with requests.get(url,headers={'User-Agent':'Mozilla/5.0','Accept':'text/html,application/json'},timeout=(8,12),stream=True) as r:
            sample=next(r.iter_content(65536),b'')
            row.update(transport='response',status=r.status_code,mime=r.headers.get('Content-Type',''),sampleBytes=len(sample),sampleSHA256=hashlib.sha256(sample).hexdigest())
    except requests.RequestException as e:
        row.update(transport=type(e).__name__)
    row['elapsedSeconds']=round(time.monotonic()-start,2)
    return row
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    rows=list(pool.map(probe,sources))
(O/'comic-transport.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf8')
summary={'sources':len(rows),'transport':dict(collections.Counter(r['transport'] for r in rows)),'status':dict(collections.Counter(str(r.get('status','none')) for r in rows)),'endToEndVerified':0}
(O/'comic-transport-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(summary,ensure_ascii=False))
