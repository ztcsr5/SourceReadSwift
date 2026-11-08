"""Snapshot committed changes and exercise patch/rollback only in an isolated directory."""
from pathlib import Path
import hashlib, json, shutil, subprocess, sys, time

ROOT = Path(__file__).resolve().parents[2]
OUT = Path('F:/SourceReadSwift/release-1.1.7')
BASE = '68b68b7abbb7bea06e7fe53d95edc89ec8ee7c79'
def git(*args): return subprocess.check_output(['git', '-C', str(ROOT), *args])
def sha(data): return hashlib.sha256(data).hexdigest()
head = git('rev-parse', 'HEAD').decode().strip()
assert not git('diff', '--name-only').strip(), 'Do not package uncommitted tracked edits'
manifest = []
for name in git('diff', '--name-only', BASE, head).decode().splitlines():
    existed = subprocess.run(['git', 'cat-file', '-e', BASE + ':' + name], cwd=ROOT, capture_output=True).returncode == 0
    before = git('show', BASE + ':' + name) if existed else None
    after = git('show', head + ':' + name)
    modified = OUT / 'MODIFIED_FILE' / name
    modified.parent.mkdir(parents=True, exist_ok=True)
    modified.write_bytes(after)
    original = OUT / 'BASELINE' / name
    if existed:
        canonical = OUT / 'CANONICAL_BASELINE' / name
        canonical.parent.mkdir(parents=True, exist_ok=True)
        canonical.write_bytes(before)
        assert original.exists(), 'Original copy-first baseline is missing: ' + name
    manifest.append({'path': name, 'existed': existed, 'baseline_git_sha256': sha(before) if existed else None,
                     'baseline_worktree_sha256': sha(original.read_bytes()) if existed else None, 'modified_sha256': sha(after),
                     'modified_worktree_sha256': sha((ROOT / name).read_bytes())})
(OUT / 'change-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf8')
(OUT / 'DIFF_FILE.patch').write_bytes(git('diff', '--binary', BASE, head))
(OUT / 'artifact-commit.json').write_text(json.dumps({'baseline': BASE, 'modified': head, 'files': len(manifest),
    'patch_bytes': 'Git canonical LF blobs', 'baseline': BASE, 'original_bytes': 'BASELINE copy-first worktree snapshot'}, indent=2), encoding='utf8')
rollback_source = Path('F:/SourceReadSwift/recovery-119/ROLLBACK.py').read_text(encoding='utf8')
assert 'recovery-119' not in rollback_source
rollback_source = rollback_source.replace("item['modified_sha256'],item['baseline_git_sha256']", "item['modified_sha256'],item.get('modified_worktree_sha256'),item['baseline_git_sha256']")
(OUT / 'ROLLBACK.py').write_text(rollback_source, encoding='utf8')
(OUT / 'ROLLBACK.ps1').write_text('param([Parameter(Mandatory=$true)][string]$Root)\n& python (Join-Path $PSScriptRoot "ROLLBACK.py") --root $Root\nexit $LASTEXITCODE\n', encoding='utf8')
log = []
def run(args, cwd):
    p = subprocess.run(args, cwd=cwd, capture_output=True, text=True, encoding='utf8', errors='replace')
    log.append({'command': args, 'cwd': str(cwd), 'stdout': p.stdout, 'stderr': p.stderr, 'exit_code': p.returncode})
    assert p.returncode == 0, p.stderr
drill = OUT / 'drills' / str(time.time_ns())
drill.mkdir(parents=True)
for item in manifest:
    if item['existed']:
        target = drill / item['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(OUT / 'CANONICAL_BASELINE' / item['path'], target)
def verify(key):
    for item in manifest:
        p = drill / item['path']
        if key.startswith('baseline_') and not item['existed']:
            assert not p.exists(), item['path']
        else:
            assert sha(p.read_bytes()) == item[key], item['path']
    log.append({'check': key, 'matched_files': len(manifest), 'result': 'PASS'})
verify('baseline_git_sha256')
for round in range(2):
    run(['git', '-c', 'core.autocrlf=false', '-c', 'core.eol=lf', 'apply', '--check', str(OUT / 'DIFF_FILE.patch')], drill)
    run(['git', '-c', 'core.autocrlf=false', '-c', 'core.eol=lf', 'apply', str(OUT / 'DIFF_FILE.patch')], drill)
    verify('modified_sha256')
    if round == 0:
        run([sys.executable, str(OUT / 'ROLLBACK.py'), '--root', str(drill), '--canonical'], drill)
        verify('baseline_git_sha256')
# A clean Windows checkout may use CRLF instead of canonical Git LF bytes.
# Exercise rollback with those exact observed modified worktree bytes too.
for item in manifest:
    shutil.copyfile(ROOT / item['path'], drill / item['path'])
verify('modified_worktree_sha256')
run([sys.executable, str(OUT / 'ROLLBACK.py'), '--root', str(drill)], drill)
verify('baseline_worktree_sha256')
run(['git', 'diff', '--check'], ROOT)
(OUT / 'VERIFICATION-local.json').write_text(json.dumps({'head': head, 'drill': str(drill),
    'scope': 'Byte reconstruction/rollback, not native runtime rollback behavior.', 'checks': log}, ensure_ascii=False, indent=2), encoding='utf8')
print('PASS patch, rollback, reapply, original worktree bytes:', len(manifest), 'files;', head)
