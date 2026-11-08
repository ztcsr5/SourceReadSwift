import json,sys
from pathlib import Path
rows=json.loads(Path('F:/SourceReadSwift/release-1.1.6/source-audit/comic-sources.json').read_text(encoding='utf8'))
for idx in map(int,sys.argv[1:]):
 s=rows[idx];print('\nINDEX',idx,s.get('bookSourceName'),s.get('bookSourceUrl'))
 for k in ('searchUrl','ruleSearch','ruleBookInfo','ruleToc','ruleContent'):
  print(k, json.dumps(s.get(k),ensure_ascii=False)[:4000])
