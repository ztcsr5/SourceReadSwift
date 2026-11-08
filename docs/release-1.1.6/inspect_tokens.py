from pathlib import Path
import sys
p=Path(sys.argv[1])
if not p.exists():
 matches=list(Path('SourceReadSwift').rglob(p.name))
 if len(matches)!=1: print('No unique file',p,[str(m) for m in matches]);raise SystemExit(1)
 p=matches[0];print('Resolved',p)
lines=p.read_text(encoding='utf-8-sig').splitlines()
seen=set()
for i,line in enumerate(lines):
 if any(t in line for t in sys.argv[2:]):
  for j in range(max(0,i-3),min(len(lines),i+6)):
   if j not in seen: print(f'{j+1}: {lines[j]}');seen.add(j)
