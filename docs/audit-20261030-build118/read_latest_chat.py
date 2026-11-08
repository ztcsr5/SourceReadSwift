import json
from pathlib import Path

records=json.loads((Path(__file__).parent/'chat-visible-text.json').read_text(encoding='utf8'))
for r in records:
    if r['idx']>=5074 and r['role']=='user':print(f"\nUSER STEP {r['idx']}\n{r['text']}")
for r in [x for x in records if x['idx']>=5074 and x['role']=='assistant'][-4:]:
    print(f"\nASSISTANT STEP {r['idx']}\n{r['text'][:6500]}")
