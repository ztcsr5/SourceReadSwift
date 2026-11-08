import json,re
from pathlib import Path
rows=json.loads(Path('F:/SourceReadSwift/release-1.1.6/source-audit/comic-sources.json').read_text(encoding='utf8'))
print(type(rows).__name__,len(rows))
for i,s in enumerate(rows):
 text=json.dumps(s,ensure_ascii=False)
 flags=[p for p in ['cookie','authorization','password','access_token','api_key','bearer','loginInfo','setCookie'] if re.search(p,text,re.I)]
 print(i,s.get('bookSourceName'), 'header='+str(bool(s.get('header'))), 'flags='+','.join(flags), 'bytes='+str(len(text)))
