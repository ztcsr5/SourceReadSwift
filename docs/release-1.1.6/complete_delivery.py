from pathlib import Path
import hashlib, json, shutil, subprocess, sys
import ci

O, H = ci.OUT, ci.ci.HEAD
finalize = Path(__file__).with_name('finalize.py')
subprocess.run([sys.executable,'-X','utf8',str(finalize)],cwd=ci.ROOT,check=True)
ipa = json.loads((O/'IPA_VERIFICATION.json').read_text(encoding='utf8'))
source = Path(ipa['path'])
dest = Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.6-build127-unsigned.ipa')
assert hashlib.sha256(source.read_bytes()).hexdigest() == ipa['sha256']
if dest.exists():
    assert hashlib.sha256(dest.read_bytes()).hexdigest() == ipa['sha256'], 'Refusing to replace a different build127'
else:
    shutil.copyfile(source,dest)
assert hashlib.sha256(dest.read_bytes()).hexdigest() == ipa['sha256']
ipa['path'] = str(dest)
(O/'IPA_VERIFICATION.json').write_text(json.dumps(ipa,ensure_ascii=False,indent=2),encoding='utf8')
subprocess.run([sys.executable,'-X','utf8',str(finalize)],cwd=ci.ROOT,check=True)
record = json.loads((O/'delivery-verification.json').read_text(encoding='utf8'))
counts = record['native_test_counts']
comic = record['comic_audit']
checkpoint = f'''# Current verified release

- Project: D:/Gemini反重力/SourceReadSwift2
- Branch: codex/release-1.1.6
- HEAD: {H}
- Release: 1.1.6 / Build127
- IPA: {dest}
- SHA256: {ipa['sha256']}
- Evidence: {O}
- XCTest: {counts}; all selected native26 cases executed, zero failures.
- Comic corpus: all 997 statically inventoried; {comic['total']} comic configurations sampled through first-result/first-chapter/first-image pipeline, {comic['decoded']} decoded first image. Remaining failures retained by stage/message, NOT declared fixed. Private corpus is not fully committed.
- Changes: opaque reader menu top; image/lazy/per-image headers + bounded loading/retry/cancellation; root high-frequency publication isolation; opt-in 30s frame-interval report; legacy-only capsule tabs + detached search; six coordinated global visual themes; four original illustrated reading backgrounds; Settings vector brand mark.
- Competitor P5 homepage layout NOT implemented; native iOS26 TabView builder unchanged.
- Physical iOS16/17/ProMotion acceptance remains pending. MinimumOS=16 verified in IPA, not a physical-device compatibility guarantee. No minimum120fps claim.
- Visual QA: real mounted screenshot attachments retained; exact inspected sheets and scope in visual-review.json.
- Copy-first baseline and isolated exact-byte patch/rollback drill preserved. Archived build126 IPA verified unchanged. Desktop build126 was absent at final check; not deleted or restored by this delivery.
- Source audit: source-audit/comic-pipeline-31.json and .csv. Source availability/empty results/unsupported rules are not equivalent to deterministic regression-test failures.
- Helper tools: docs/release-1.1.6/*.py remain local untracked; final truth is delivery-verification.json, not the initial tracked RECOVERY.md.
'''
(O/'RECOVERY-COMPLETE.md').write_text(checkpoint,encoding='utf8')
Path('F:/SourceReadSwift/RECOVERY-CURRENT.md').write_text(checkpoint,encoding='utf8')
print('PASS release delivered:', dest)
