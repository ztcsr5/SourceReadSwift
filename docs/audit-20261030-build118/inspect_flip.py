from pathlib import Path
import sys
sys.stdout.reconfigure(encoding='utf-8')
for spec in sys.argv[1:]:
    parts = spec.split(':')
    p = Path(parts[0])
    start = int(parts[1]) if len(parts)>1 else 1
    end = int(parts[2]) if len(parts)>2 else 100000
    print('\nFILE', p)
    for i, line in enumerate(p.read_text(encoding='utf-8').splitlines(), 1):
        if start <= i <= end: print(f'{i}: {line}')
