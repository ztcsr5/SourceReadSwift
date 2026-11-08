from pathlib import Path
import hashlib, json, re
import ci

O, R, H = ci.OUT, ci.ROOT, ci.ci.HEAD
status = json.loads((O/'ci-status.json').read_text(encoding='utf8'))
assert status['head'] == H
runs = {r['name']:r for r in status['runs']}
assert all(runs[n]['conclusion']=='success' and runs[n]['head_sha']==H for n in ['iOS','Unsigned IPA'])
folder = O/'native-evidence'/H
counts, logs = {}, {}
for name in ['xcodebuild-test.log','native-tab-test.log']:
    log = (folder/name).read_text(encoding='utf8', errors='replace'); logs[name] = log
    assert '** TEST SUCCEEDED **' in log, name
    rows = re.findall(r'Executed (\d+) tests?,(?: with \d+ tests? skipped and)? with (\d+) failures?', log)
    rows += re.findall(r'Executed (\d+) tests?, with \d+ tests? skipped and (\d+) failures?', log)
    assert rows and all(int(f)==0 for _,f in rows), (name, rows)
    counts[name] = max(int(n) for n,_ in rows)
legacy, native = logs['xcodebuild-test.log'], logs['native-tab-test.log']
assert not re.search(r'with [1-9]\d* tests? skipped|Test Case .* skipped', native)
workflow = (R/'.github/workflows/ios.yml').read_text(encoding='utf8')
native_suites = re.findall(r'-only-testing:SourceReadSwiftTests/(\w+)', workflow)
suites = {}
for suite in native_suites + ['ReaderScrollHeaderTests','ReaderExitSwipeTests']:
    methods = re.findall(r'func (test\w+)\(', (R/f'SourceReadSwiftTests/{suite}.swift').read_text(encoding='utf8'))
    assert methods, suite
    suites[suite] = methods
    for method in methods:
        selected = [native] if suite == 'TabChromeRegressionTests' else [legacy,native] if suite in native_suites else [legacy]
        for log in selected:
            assert re.search(r'Test Case .*'+suite+'.*'+re.escape(method)+r'.*passed',log), (suite,method)
assert counts['native-tab-test.log'] == sum(len(suites[s]) for s in native_suites), counts
assert counts['xcodebuild-test.log'] >= 1495, counts
visual = json.loads((folder/'visual-review.json').read_text(encoding='utf8'))
assert visual['head']==H and visual['status']=='PASS'
pixels = json.loads((folder/'visual-pixel-checks.json').read_text(encoding='utf8'))
assert pixels['head']==H and len(pixels['checks'])==28
audit = json.loads((O/'source-audit/comic-pipeline-31.json').read_text(encoding='utf8'))
assert audit['head']==H and audit['total']==31
ipa = json.loads((O/'IPA_VERIFICATION.json').read_text(encoding='utf8'))
assert ipa['commit']==H and ipa['version']=='1.1.6' and ipa['build']=='127'
assert hashlib.sha256(Path(ipa['path']).read_bytes()).hexdigest()==ipa['sha256']
assert json.loads((O/'VERIFICATION-local.json').read_text(encoding='utf8'))['head']==H
assert json.loads((O/'graphify-out/audit.json').read_text(encoding='utf8'))['head']==H
old = Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.5-build126-unsigned.ipa')
old_archive = Path('F:/SourceReadSwift/release-1.1.5/IPA/bcb22284458db6a7bc8f6ae68a3ac60936df20a9/SourceReadSwift-1.1.5-build126-unsigned.ipa')
old_sha = '32bd9a59af64c45b081fd2e5755d61b0b4e29982c1f797790993321fa97ef437'
assert hashlib.sha256(old_archive.read_bytes()).hexdigest()==old_sha
if old.exists(): assert hashlib.sha256(old.read_bytes()).hexdigest()==old_sha
record = {'head':H, 'version':'1.1.6', 'build':127, 'native_test_counts':counts, 'failures':0,
          'baseline_ipa':{'archive':str(old_archive),'sha256':old_sha,'desktop_copy_present_at_delivery':old.exists(),'note':'Desktop build126 was absent at final check; no deletion or restoration performed. Verified archived build126 remains unchanged.'},
          'iOS26_skipped':0, 'verified_suites':suites, 'visual_review':visual, 'ipa':ipa,
          'comic_audit':{k:v for k,v in audit.items() if k!='rows'},
          'runs':{n:runs[n]['html_url'] for n in ['iOS','Unsigned IPA']},
          'scope':'Opaque reader menu top; comic image parsing/headers/retry/cancellation; root publication isolation and opt-in frame interval instrumentation; six global themes; four original reading backgrounds; legacy-only tab/search layout. Competitor homepage layout not implemented.',
          'limitations':['No minimum 120fps guarantee: simulator tests and callback histograms do not establish physical-device render performance.',
                         'iOS16 minimum deployment verified in IPA; physical iOS16/17 acceptance, including reported iOS17 iPhone15Pro reproduction, remains pending.',
                         'All 997 sources statically inventoried; 31 comic source configurations sampled live. First-result/first-chapter/first-image success is not whole-source compatibility.',
                         'Patch/rollback drill verifies exact tracked bytes on isolated copies, not a full runtime rollback drill.'],
          'artifacts':{n:str(O/p) for n,p in [('MODIFIED_FILE','MODIFIED_FILE'),('DIFF_FILE','DIFF_FILE.patch'),('VERIFICATION','VERIFICATION.txt'),('ROLLBACK','ROLLBACK.py')]}}
(O/'delivery-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
(O/'VERIFICATION.txt').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n\n'+
    '\n'.join(x for x in native.splitlines() if 'Test Case' in x or 'Executed ' in x or '** TEST' in x)+
    '\n\n'+'\n'.join(x for x in legacy.splitlines() if any(k in x for k in ['COMIC_AUDIT','COMIC_ROW_B64','Executed ','** TEST'])),encoding='utf8')
print(json.dumps({k:record[k] for k in ['head','version','build','native_test_counts','ipa','runs','comic_audit']},ensure_ascii=False,indent=2))
