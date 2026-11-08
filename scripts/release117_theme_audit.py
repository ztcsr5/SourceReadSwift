"""Read-only theme coverage inventory. Usage: python -X utf8 scripts/release117_theme_audit.py"""
from pathlib import Path
import json
import sys

ROOT=Path(__file__).resolve().parents[1]
for parent in [ROOT.parent,ROOT,*sorted((ROOT/'SourceReadSwift').rglob('AGENTS.md'))]:
    p=parent if parent.name=='AGENTS.md' else parent/'AGENTS.md'
    if p.exists():print('INSTRUCTIONS',p,p.read_text(encoding='utf-8'))
rows=[]
for p in sorted((ROOT/'SourceReadSwift').rglob('*.swift')):
    text=p.read_text(encoding='utf-8')
    if 'some View' not in text or p.name.endswith('.bak'):continue
    signals=['Form {','List {','NavigationStack {','pageBackground()','systemGroupedBackground','secondarySystemGroupedBackground','Color.white','Color.black']
    found={s:[i for i,l in enumerate(text.splitlines(),1) if s in l] for s in signals if s in text}
    if found:rows.append({'file':str(p.relative_to(ROOT)),**found})
out=Path('F:/SourceReadSwift/release-1.1.7/theme17');out.mkdir(parents=True,exist_ok=True)
(out/'coverage-before.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
for r in rows:
    if ('Form {' in r or 'List {' in r) and 'pageBackground()' not in r:print(json.dumps(r,ensure_ascii=False))
print('UI files',len(rows))
if '--boundaries' in sys.argv:
    for row in rows:
        if 'Form {' not in row and 'List {' not in row:continue
        p=ROOT/row['file'];lines=p.read_text(encoding='utf-8').splitlines()
        print('\nFILE',row['file'])
        for i,l in enumerate(lines):
            if any(s in l for s in ['.navigationTitle(','.listStyle(','.scrollContentBackground(','.pageBackground()', '.navigationBarTitleDisplayMode(']):
                print('\n'.join(f'{n+1}: {lines[n]}' for n in range(max(0,i-3),min(len(lines),i+2))))
