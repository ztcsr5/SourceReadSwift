from pathlib import Path
import sys
lines=Path('F:/SourceReadSwift/release-1.1.2/job-'+sys.argv[1]+'.log').read_text(encoding='utf8',errors='replace').splitlines()
start=next((i for i,l in enumerate(lines) if "Test Suite 'Selected tests' started" in l),len(lines)-130)
print('\n'.join(lines[start:start+110]))
