"""Copy-first item17 checkpoint. Usage: python -X utf8 scripts/release117_theme_checkpoint.py"""
from pathlib import Path
import hashlib,json,subprocess,shutil
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('F:/SourceReadSwift/release-1.1.7/theme17')
head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
assert head=='a37e8b871a718c41aab3246c699e7344a93f212f'
assert not subprocess.check_output(['git','diff','--name-only'],cwd=ROOT).strip()
manifest=[]
for name in subprocess.check_output(['git','ls-files'],cwd=ROOT,text=True,encoding='utf-8').splitlines():
    p=ROOT/name
    if not p.is_file():continue
    target=OUT/'BASELINE'/name
    if not target.exists():target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
    assert p.read_bytes()==target.read_bytes()
    manifest.append({'path':name,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
(OUT/'baseline.json').write_text(json.dumps({'head':head,'files':manifest},ensure_ascii=False,indent=2),encoding='utf-8')
print('BASELINE verified',head,len(manifest),'files')
