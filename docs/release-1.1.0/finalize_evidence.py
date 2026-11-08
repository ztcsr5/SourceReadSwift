from pathlib import Path
import hashlib, io, json, re, shutil, subprocess, zipfile
import ci

OUT, ROOT, HEAD = ci.OUT, ci.ROOT, ci.ci.HEAD
status = json.loads((OUT / 'ci-status.json').read_text(encoding='utf8'))
assert status['head'] == HEAD
runs = {r['name']: r for r in status['runs']}
assert len(runs) == 2 and all(r['conclusion'] == 'success' for r in runs.values())
ipa = json.loads((OUT / 'IPA_VERIFICATION.json').read_text(encoding='utf8'))
assert ipa['commit'] == HEAD and hashlib.sha256(Path(ipa['path']).read_bytes()).hexdigest() == ipa['sha256']
native = OUT / 'native-evidence'
native.mkdir(exist_ok=True)
for artifact in ci.ci.api(f"actions/runs/{runs['iOS']['id']}/artifacts")['artifacts']:
    if not artifact['name'].startswith('ios-test-evidence-'): continue
    target = native / (str(artifact['id']) + '.zip')
    if not target.exists(): target.write_bytes(ci.ci.signed_download(f"actions/artifacts/{artifact['id']}/zip"))
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None
        for item in z.infolist():
            resolved = (native / item.filename).resolve()
            assert resolved.is_relative_to(native.resolve())
            if not item.is_dir() and item.filename.endswith('.log'):
                resolved.parent.mkdir(parents=True, exist_ok=True)
                resolved.write_bytes(z.read(item))
    break
else: raise SystemExit('Missing native XCTest artifact')
test_logs = list(native.rglob('xcodebuild-test.log'))
assert len(test_logs) == 1
test_text = test_logs[0].read_text(encoding='utf8', errors='replace')
summary = re.findall(r'Executed (\d+) tests?, with (\d+) failures?[^\n]*', test_text)
assert summary, 'No literal XCTest totals found'
total = max(int(n) for n, failures in summary)
assert total >= 1374
assert all(failures == '0' for n, failures in summary)
assert '** TEST SUCCEEDED **' in test_text
regression = re.findall(r"Test Suite 'Release110RegressionTests'.*?Executed (\d+) tests?, with (\d+) failures?", test_text, re.S)
local = json.loads((OUT / 'VERIFICATION-local.json').read_text(encoding='utf8'))
assert local['head'] == HEAD
file_count = len(json.loads((OUT / 'change-manifest.json').read_text(encoding='utf8')))
for name in ('ISSUES.md', 'DEVICE_ACCEPTANCE.md', 'PARSER_RESEARCH.md', 'REPRODUCE.md'):
    source = Path(__file__).with_name(name)
    text = source.read_text(encoding='utf8').replace('e06501b3137c1a639ee0d40b3e3acc93934cf94c', HEAD)
    source.write_text(text, encoding='utf8')
    (OUT / name).write_text(text, encoding='utf8')
for name in ('package_release.py', 'download_ipa.py', 'browser_qa.py', 'motion_regression.py', 'finalize_evidence.py'):
    dest = OUT / 'reproduction' / name
    dest.parent.mkdir(exist_ok=True)
    shutil.copyfile(Path(__file__).with_name(name), dest)
record = {'head': HEAD, 'baseline': '71156be1ac148d6328dccc2844ed2555a41313b0',
          'tests': total, 'failures': 0, 'new_regression_suite_totals': regression,
          'runs': {k: {'id':v['id'], 'url':v['html_url'], 'conclusion':v['conclusion']} for k,v in runs.items()},
          'ipa': ipa, 'native_artifact': str(target), 'test_log': str(test_logs[0]),
          'ios16_runtime': 'NOT RUN; minimum deployment and IPA MinimumOSVersion are 16.0',
          'device_fps_and_local_crash_reproduction': 'NOT RUN; code changes/behavioral isolation are not device proof'}
(OUT / 'release-verification.json').write_text(json.dumps(record, ensure_ascii=False, indent=2), encoding='utf8')
report = f'''纸间 1.1.0 / Build120 verification
Source commit: {HEAD}
Baseline: {record['baseline']}
Simulator build + XCTest: PASS, {total} tests, 0 failures.
Unsigned device build/package: PASS, same commit.
IPA: {ipa['path']}
Version/build/minimum iOS: {ipa['version']} / {ipa['build']} / {ipa['minimum_os']}
SHA256: {ipa['sha256']}
Bytes: {ipa['bytes']}
iOS CI: {runs['iOS']['html_url']}
IPA CI: {runs['Unsigned IPA']['html_url']}
Literal test log: {test_logs[0]}
Native evidence zip (xcresult + logs): {target}

Local executed checks:
- Actual-source LAN HTML: desktop light, phone-width light, desktop dark, tabs and overflow; no JS page errors. See browser-qa.json.
- Actual-source reader DOM: exact chapter29 jump; old revision ignored; missing target rejected; speech still animated; newer explicit jump cancels old motion/fallback.
- Motion regression: previous e06501b moves new target0 to200; modified stays0. See motion-regression.json.
- Binary patch reconstruction, canonical rollback, reapply and original worktree-byte rollback: PASS across {file_count} changed files. See VERIFICATION-local.json for literal stdout/stderr/exit codes.
- Git diff --check: PASS. Swift syntax comparison is advisory; native compiler is the authoritative check.

NOT RUN:
- iOS16.x physical-device runtime and every-feature end-to-end acceptance. Follow DEVICE_ACCEPTANCE.md.
- Device FPS/Instruments profiling. Search/startup improvements are not a measured FPS claim.
- Original local-detail crash reproduction/crash-stack diagnosis. New path isolates reader recursion risk; not a confirmed crash root cause.
- Real phone LAN source push in browser QA (fixed API fixtures were used).
- All-source Legado differential compatibility campaign; no global success rate claimed.
- Native baseline/modified/rollback behavior trio. The isolated rollback drill verifies exact bytes, not device runtime behavior.

MODIFIED_FILE: {OUT / 'MODIFIED_FILE'}
DIFF_FILE: {OUT / 'DIFF_FILE.patch'}
VERIFICATION: {OUT / 'VERIFICATION.txt'}
ROLLBACK: {OUT / 'ROLLBACK.ps1'} (Python companion required; unknown later edits are refused.)
'''
(OUT / 'VERIFICATION.txt').write_text(report, encoding='utf8')
print(json.dumps({'head': HEAD, 'tests':total, 'failures':0, 'report':str(OUT / 'VERIFICATION.txt'), 'ipa':ipa['path']}, ensure_ascii=False))
