import subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2]
paths=subprocess.check_output(['git','diff','--name-only','71156be','--diff-filter=A'],cwd=R).decode().splitlines()
paths=[p for p in paths if '.bak' in p]
assert len(paths)==8,paths
subprocess.run(['git','rm','--cached','--',*paths],cwd=R,check=True)
assert all((R/p).exists() for p in paths)
print('Only index entries removed; all 8 existing user backups remain on disk.')
