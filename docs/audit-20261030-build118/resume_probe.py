from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
print('ARTIFACTS', flush=True)
for path in Path(__file__).resolve().parent.iterdir():
    print(path.name, path.stat().st_size, flush=True)
print('STATUS', subprocess.check_output(['git','-C',str(ROOT),'status','--short']).decode('utf-8'), flush=True)
for root in (Path('F:/Codex/.codex/sessions'),Path('C:/Users/Edc21/.codex/sessions'),Path('F:/Codex/.codex/archived_sessions'),Path('C:/Users/Edc21/.codex/archived_sessions')):
    if root.exists():
        for path in root.rglob('*.jsonl'):
            if any(x in path.name for x in ('01a1870b-2d3c-7541-97a5-cf146a4daee9','01a15848-1328-7f23-a24e-509b26c7c1a9')):
                print('HISTORY',path,path.stat().st_size, flush=True)
