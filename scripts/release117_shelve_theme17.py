"""Preserve this turn's theme17 edits then restore its copy-first baseline only.
Usage: python -X utf8 scripts/release117_shelve_theme17.py
No git reset/clean/stash, no changes to unrelated untracked artifacts.
"""
from pathlib import Path
import hashlib,json,subprocess,shutil,time
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('F:/SourceReadSwift/release-1.1.7/theme17')
base=json.loads((OUT/'baseline.json').read_text(encoding='utf-8'))
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()==base['head']
names=subprocess.check_output(['git','diff','--name-only'],cwd=ROOT,text=True,encoding='utf-8').splitlines()
allowed={r['path'].replace('\\','/') for r in json.loads((OUT/'page-boundaries.json').read_text(encoding='utf-8'))}
allowed|={r['file'].replace('\\','/') for r in json.loads((OUT/'section-rows.json').read_text(encoding='utf-8'))}
allowed|={'SourceReadSwift/Shared/DesignSystem/AppTheme.swift','SourceReadSwift/Features/Settings/AppearanceSettingsView.swift'}
assert set(names)<=allowed
shelf=OUT/'SHELVED'/str(time.time_ns());shelf.mkdir(parents=True)
patch=subprocess.check_output(['git','diff','--binary'],cwd=ROOT)
(shelf/'tracked.patch').write_bytes(patch)
hashes={r['path']:r['sha256'] for r in base['files']}
for name in names:
    p=ROOT/name;backup=OUT/'BASELINE'/name
    assert hashlib.sha256(backup.read_bytes()).hexdigest()==hashes[name]
    copy=shelf/name;copy.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,copy)
for name in names:shutil.copyfile(OUT/'BASELINE'/name,ROOT/name)
new=ROOT/'SourceReadSwift/Shared/DesignSystem/AppThemeSurface.swift'
if new.exists():
    assert subprocess.run(['git','ls-files','--error-unmatch',str(new)],cwd=ROOT,capture_output=True).returncode!=0
    target=shelf/new.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(new,target)
    assert target.read_bytes()==new.read_bytes()
    new.unlink()
assert not subprocess.check_output(['git','diff','--name-only'],cwd=ROOT).strip()
receipt={'baseline':base['head'],'shelf':str(shelf),'restored_tracked_files':len(names),'state':'Item17 deferred by user; items3/4/11/12 first'}
(OUT/'SHELVED.json').write_text(json.dumps(receipt,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(receipt,ensure_ascii=False))
