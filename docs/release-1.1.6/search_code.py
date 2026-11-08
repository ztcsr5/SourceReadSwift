from pathlib import Path
import sys
for root in [Path('SourceReadSwift'),Path('SourceReadSwiftTests')]:
    for path in root.rglob('*.swift'):
        lines = path.read_text(encoding='utf-8-sig').splitlines()
        for i,line in enumerate(lines):
            if any(token in line for token in sys.argv[1:]):
                print(f'{path}:{i+1}: {line}')
