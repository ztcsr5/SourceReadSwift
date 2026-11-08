from pathlib import Path
import collections, hashlib, json
p=Path('D:/QQ游戏/all_book_sources.json')
raw=p.read_bytes(); data=json.loads(raw.decode('utf-8-sig'))
if isinstance(data,dict):
    data=next((v for v in data.values() if isinstance(v,list)),[data])
sources=[x for x in data if isinstance(x,dict)]
counts=collections.Counter(str(x.get('bookSourceType','missing')) for x in sources)
comics=[x for x in sources if str(x.get('bookSourceType'))=='2']
out=Path('F:/SourceReadSwift/release-1.1.6/source-audit');out.mkdir(parents=True,exist_ok=True)
(out/'comic-sources.json').write_text(json.dumps(comics,ensure_ascii=False,indent=2),encoding='utf8')
report={'input':str(p),'sha256':hashlib.sha256(raw).hexdigest(),'total':len(sources),'types':dict(counts),'comicCount':len(comics),
        'comics':[{'name':s.get('bookSourceName'),'url':s.get('bookSourceUrl'),'search':s.get('searchUrl'),'content':s.get('ruleContent'),'header':s.get('header')} for s in comics]}
(out/'inventory.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k!='comics'},ensure_ascii=False))
for x in report['comics'][:8]: print(json.dumps(x,ensure_ascii=False)[:1700])
