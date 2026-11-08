import json
from pathlib import Path
rows=json.loads(Path('F:/SourceReadSwift/release-1.1.6/source-audit/comic-sources.json').read_text(encoding='utf8'))
for i,s in enumerate(rows):
 print(i,'header=',str(s.get('header',''))[:500], 'login=',str(s.get('loginUrl',''))[:150])
