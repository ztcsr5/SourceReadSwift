from pathlib import Path
import sys
ROOT=Path(__file__).resolve().parents[2]
for arg in sys.argv[1:]:
    parts=arg.replace('@','|').replace('~','|').split('|'); p=ROOT/parts[0]
    lines=p.read_text(encoding='utf8').splitlines()
    lo=int(parts[1]) if len(parts)>1 else 1
    hi=int(parts[2]) if len(parts)>2 else len(lines)
    print('\nFILE',p)
    for i in range(lo-1,min(hi,len(lines))):print(f'{i+1}: {lines[i]}')
