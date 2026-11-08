from pathlib import Path
import requests, json, hashlib
out=Path('F:/SourceReadSwift/release-1.1.1/aidoku');out.mkdir(parents=True,exist_ok=True)
url='https://aidoku-community.github.io/sources/index.min.json'
r=requests.get(url,timeout=30);r.raise_for_status()
(out/'index.json').write_bytes(r.content)
d=r.json()
summary={'url':url,'sha256':hashlib.sha256(r.content).hexdigest(),'root_type':type(d).__name__,
         'count':len(d),'sample':d[:1] if isinstance(d,list) else {k:type(v).__name__ for k,v in d.items()}}
(out/'probe.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(summary,ensure_ascii=False,indent=2)[:2400])
