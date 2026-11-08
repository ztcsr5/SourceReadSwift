from pathlib import Path
import sys
root=Path(__file__).resolve().parents[2]
terms=sys.argv[1:]
for directory in ['SourceReadSwift','SourceReadSwiftTests']:
 for p in (root/directory).rglob('*.swift'):
  for i,line in enumerate(p.read_text(encoding='utf-8').splitlines(),1):
   if any(t in line for t in terms): print(f'{p.relative_to(root)}:{i}: {line}')
