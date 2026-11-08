from pathlib import Path
import json, subprocess, sys, time
ROOT = Path(__file__).resolve().parents[2]
OUT = Path('F:/SourceReadSwift/release-1.1.7')
last = ''
for _ in range(30):
    p = subprocess.run([sys.executable, '-X', 'utf8', str(Path(__file__).with_name('ci.py'))], cwd=ROOT,
                       capture_output=True, text=True, encoding='utf8')
    if p.returncode:
        print(p.stdout + p.stderr, flush=True)
        raise SystemExit(p.returncode)
    if p.stdout != last:
        print(p.stdout, flush=True)
        last = p.stdout
    status = json.loads((OUT / 'ci-status.json').read_text(encoding='utf8'))
    if len(status['runs']) >= 2 and all(r['status'] == 'completed' for r in status['runs']):
        raise SystemExit(0 if all(r['conclusion'] == 'success' for r in status['runs']) else 1)
    time.sleep(60)
raise SystemExit('CI monitoring reached 30 minutes; check the saved status, not a success claim.')
