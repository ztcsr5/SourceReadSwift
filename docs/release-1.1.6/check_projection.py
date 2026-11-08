import json,re
from pathlib import Path
rows=json.loads(Path('F:/SourceReadSwift/release-1.1.6/source-audit/comic-sources.json').read_text(encoding='utf8'))
projection=json.loads(Path('SourceReadSwiftTests/Fixtures/comic-sources-20261101.json').read_text(encoding='utf8'))
print('source6 original keys',sorted(rows[6]))
print('all original keys', sorted(set().union(*(set(s) for s in rows))))
for i,(source,projected) in enumerate(zip(rows,projection)):
    code=json.dumps({k:source.get(k) for k in ['ruleContent','ruleToc','ruleSearch','ruleBookInfo','jsLib','loginUrl','searchUrl']},ensure_ascii=False)
    referenced=set(re.findall(r'source\.([A-Za-z_$][A-Za-z0-9_$]*)',code))
    omitted=sorted((set(source)-set(projected))&referenced)
    if omitted:print(i,source['bookSourceName'],'omitted-referenced',omitted)
    for key in ['variable','variables','loginInfo','loginHeader','authorization','customConfig']:
        if source.get(key):print(i,'nonempty',key,'type',type(source[key]).__name__,'length',len(str(source[key])))
