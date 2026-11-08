from pathlib import Path
import json
for p in Path('F:/SourceReadSwift/release-1.1.6').glob('**/comic-pipeline-31.json'):
    print(p)
    data = json.loads(p.read_text(encoding='utf8'))
    if isinstance(data, dict):
        print('keys', list(data)); continue
    for row in data:
        if row.get('index') in [3, 5, 11, 12, 13, 17, 29]: print(json.dumps(row,ensure_ascii=False))
for p in Path('SourceReadSwift').rglob('*.swift'):
    text=p.read_text(encoding='utf8')
    if 'struct ComicImageRequest' in text: print('IMAGE_REQUEST',p)
