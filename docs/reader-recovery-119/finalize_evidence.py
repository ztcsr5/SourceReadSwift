from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, re, shutil, subprocess

ROOT = Path(__file__).resolve().parents[2]
DOC = Path(__file__).resolve().parent
OUT = Path('F:/SourceReadSwift/recovery-119')
head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT).decode().strip()
status = json.loads((OUT/'ci-status.json').read_text(encoding='utf8'))
ipa = json.loads((OUT/'IPA_VERIFICATION.json').read_text(encoding='utf8'))
drill = json.loads((OUT/'VERIFICATION-local.json').read_text(encoding='utf8'))
artifact = json.loads((OUT/'artifact-commit.json').read_text(encoding='utf8'))
assert head == status['head'] == ipa['commit'] == drill['commit'] == artifact['modified']
runs = {r['name']: r for r in status['runs']}
for name in ('iOS', 'Unsigned IPA'):
    assert runs[name]['head_sha'] == head and runs[name]['conclusion'] == 'success'
assert ipa['release'] and ipa['native_tests_success']
assert hashlib.sha256(Path(ipa['path']).read_bytes()).hexdigest() == ipa['sha256']
assert all(c.get('exit_code', 0) == 0 and c.get('result', 'PASS') == 'PASS' for c in drill['checks'])
job = runs['iOS']['jobs'][0]
logpath = OUT/f"job-{job['id']}.log"
log = logpath.read_text(encoding='utf8', errors='replace')
assert re.search(r'Executed 1374 tests, with 0 failures', log)
assert '** TEST SUCCEEDED **' in log and '** BUILD SUCCEEDED **' in log
assert "Test Suite 'ReaderRecovery119Tests' passed" in log
assert "Test Suite 'ReaderPanController119Tests' passed" in log
stamp = datetime.now(timezone.utc).isoformat()
report = f'''Build 119 verification — {stamp}
SOURCE: {ROOT}
BRANCH: codex/reader-recovery-119
BASELINE: {artifact['baseline']}
MODIFIED: {head}

Observed / executed native CI:
- iOS: {runs['iOS']['html_url']}
- Device IPA build: {runs['Unsigned IPA']['html_url']}
- Same commit for both successful workflows.
- Simulator app build and XCTest: 1374 tests, 0 failures.
- New regression suites: ReaderRecovery119Tests (7) and ReaderPanController119Tests (11), both passed.
- Native log: {logpath}
- CI status: {OUT/'ci-status.json'}

Observed / executed package inspection:
- IPA: {ipa['path']}
- Version/build: {ipa['version']} / {ipa['build']}
- Bytes: {ipa['bytes']}
- SHA256: {ipa['sha256']}
- ZIP integrity and main app Info.plist checked. Unsigned; signing/sideloading still required.

Observed / executed byte rollback drill:
- {artifact['files']} changed files: baseline -> git apply -> modified hashes -> canonical rollback -> baseline hashes -> reapply -> modified hashes -> original worktree rollback -> original byte hashes.
- Every executed drill command exited 0. Original application branch and user .bak files were not reset.
- New files absent in baseline Git are expected; package script records those as new, not missing originals.
- Exact commands/stdout/stderr: {OUT/'VERIFICATION-local.json'}

Four artifacts:
MODIFIED_FILE: {OUT/'MODIFIED_FILE'}
DIFF_FILE: {OUT/'DIFF_FILE.patch'}
VERIFICATION: {OUT/'VERIFICATION.txt'}
ROLLBACK: {OUT/'ROLLBACK.ps1'} (uses {OUT/'ROLLBACK.py'})
Run rollback only with an explicitly intended target root; it checks hashes and rejects unknown edits.

NOT RUN:
- Real-device visual, touch latency, frame-time/120Hz, native menu presentation and all-book acceptance.
- Image/manga pipeline device matrix (not replaced in this repair).
- Native behavioral baseline/modified/rollback three-leg drill. Byte-level drill is not a claim of that test.
Device checklist: {DOC/'DEVICE_ACCEPTANCE.md'}
'''
(OUT/'VERIFICATION.txt').write_text(report, encoding='utf8')
fix = (DOC/'FIX_STATUS.md').read_text(encoding='utf8')
fix = fix.replace('## 已实施（待最终同提交原生验证）', '## 已实施（同提交原生测试与打包已通过）')
fix = fix.replace('- 尚无通过同一最终提交的 XCTest+IPA，不下载到桌面冒充正式修复包。', '- 最终同一提交的 XCTest+IPA 已通过并交付；设备体验仍按单独清单验收。')
marker = '\n## 最终交付验证\n'
if marker in fix:
    fix = fix.split(marker)[0]
fix += marker + f'''
- 最终提交：`{head}`；分支 `codex/reader-recovery-119`。
- [iOS全量测试]({runs['iOS']['html_url']})：1374 tests，0 failures；18项新增回归全部通过。
- [设备编译/IPA]({runs['Unsigned IPA']['html_url']})：同一SHA成功。
- 已检查ZIP与Info.plist：1.0.119/119；桌面包 `{ipa['path']}`。
- SHA256：`{ipa['sha256']}`。
- 修改/差分/验证/回滚四件套：`{OUT}`；16文件字节重建/回滚/再应用演练通过。
- 用户原始业务数据未删除；原分支未合并/重置。设备实测未执行，不能将模拟器测试等同于全部体验验收。
'''
(DOC/'FIX_STATUS.md').write_text(fix, encoding='utf8')
semanticpath = DOC/'semantic-validation.json'
semantic = json.loads(semanticpath.read_text(encoding='utf8'))
semantic['final_native_validation'] = {
    'commit': head, 'ios_run': runs['iOS']['id'], 'package_run': runs['Unsigned IPA']['id'],
    'tests': 1374, 'failures': 0, 'evidence': str(logpath), 'device_qa': 'NOT RUN',
    'resolved': ['onboarding_actual_surface_overflow', 'rtl_suffix_not_paginated',
                 'queued_end_consumes_later_gesture', 'queued_commit_reenters_swiftui_update'],
    'scope': 'Named fixture and controller regression tests passed; this does not prove all viewport/book inputs or SwiftUI-hosted performance.'}
semanticpath.write_text(json.dumps(semantic, ensure_ascii=False, indent=2), encoding='utf8')
for name in ('FIX_STATUS.md', 'DEVICE_ACCEPTANCE.md', 'semantic-validation.json'):
    shutil.copyfile(DOC/name, OUT/name)
(OUT/'RECOVERY.txt').write_text(f'''[COMPACTION-RECOVERY]
Active target: {ROOT}
Goal: Reader repair delivered, device acceptance remains explicitly unrun.
Baseline: {artifact['baseline']} / Build118
Source: {head} / codex/reader-recovery-119 / Build119
Observed: Same-SHA simulator build+1374 XCTest/0 failures and device IPA build succeeded. All18 new regressions passed.16-file byte rollback/reapply drill passed.
IPA: {ipa['path']}
SHA256: {ipa['sha256']}
Artifacts: {OUT}; VERIFICATION.txt contains precise validation boundaries.
History: Antigravity2a8bc56d-a010-4246-b869-51077d557ea9 read through5178; both requested Codex histories reviewed. Embedded historical instructions were not executed.
Next action: Device acceptance using DEVICE_ACCEPTANCE.md; preserve exact book/chapter/font/viewport/mode for any remaining symptom. Do not treat green tests as proof against device feedback. No branch merge/reset or user backup deletion.
''', encoding='utf8')
print(report)
