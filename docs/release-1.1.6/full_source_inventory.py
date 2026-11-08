from pathlib import Path
import json,collections,hashlib
p=Path('D:/QQ游戏/all_book_sources.json')
data=json.loads(p.read_text(encoding='utf-8-sig'));out=Path('F:/SourceReadSwift/release-1.1.6/source-audit')
rows=[]
for i,s in enumerate(data):
 rules={k:s.get(k) for k in ('ruleSearch','ruleBookInfo','ruleToc','ruleContent','ruleExplore')}
 text=json.dumps(rules,ensure_ascii=False)
 rows.append({'index':i,'name':s.get('bookSourceName'),'type':s.get('bookSourceType',0),
 'hasBaseURL':bool(s.get('bookSourceUrl')),'hasSearchURL':bool(s.get('searchUrl')),
 'hasExploreURL':bool(s.get('exploreUrl')),'ruleStages':[k for k,v in rules.items() if v],
 'javascriptInRules':('@js:' in text or '<js>' in text),'hasImageDecode':bool((s.get('ruleContent') or {}).get('imageDecode')) if isinstance(s.get('ruleContent'),dict) else False,
 'status':'STATIC_INVENTORY_ONLY; not a live pipeline verdict'})
(out/'all-997-static-inventory.json').write_text(json.dumps({'input_sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'count':len(rows),'sources':rows},ensure_ascii=False,indent=2),encoding='utf8')
print('Inventory',len(rows),'missingBase',sum(not r['hasBaseURL'] for r in rows),'noSearchOrExplore',sum(not r['hasSearchURL'] and not r['hasExploreURL'] for r in rows),'JS',sum(r['javascriptInRules'] for r in rows),'imageDecode',sum(r['hasImageDecode'] for r in rows))
