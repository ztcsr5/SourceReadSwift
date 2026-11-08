from pathlib import Path
import hashlib, io, json, re, zipfile
import ci
O, R, H = ci.OUT, ci.ROOT, ci.ci.HEAD
status=json.loads((O/'ci-status.json').read_text(encoding='utf8'))
assert status['head']==H
runs={r['name']:r for r in status['runs']}
assert all(runs[n]['conclusion']=='success' and runs[n]['head_sha']==H for n in ['iOS','Unsigned IPA'])
folder=O/'native-evidence'/H;folder.mkdir(parents=True,exist_ok=True)
for artifact in ci.ci.api(f"actions/runs/{runs['iOS']['id']}/artifacts")['artifacts']:
    if not artifact['name'].startswith(('ios-test-evidence-', 'ios26-tab-evidence-')):continue
    archive=ci.ci.signed_download(f"actions/artifacts/{artifact['id']}/zip")
    (folder/(artifact['name']+'.zip')).write_bytes(archive)
    with zipfile.ZipFile(io.BytesIO(archive)) as z:
        assert z.testzip() is None
        for name in z.namelist():
            if Path(name).name in ['xcodebuild-test.log','native-tab-test.log']:
                (folder/Path(name).name).write_bytes(z.read(name))
counts={}
for name in ['xcodebuild-test.log','native-tab-test.log']:
    log=(folder/name).read_text(encoding='utf8',errors='replace')
    assert '** TEST SUCCEEDED **' in log,name
    rows=[(int(n),int(f)) for n,f in re.findall(r'Executed (\d+) tests?,(?: with \d+ tests? skipped and)? with (\d+) failures?',log)]
    # XCTest changes the grammar when a suite contains skipped tests.
    rows += [(int(n),int(f)) for n,f in re.findall(r'Executed (\d+) tests?, with \d+ tests? skipped and (\d+) failures?',log)]
    assert rows and all(f==0 for _,f in rows),(name,rows)
    counts[name]=max(n for n,_ in rows)
native=(folder/'native-tab-test.log').read_text(encoding='utf8',errors='replace')
assert counts['native-tab-test.log']==15
assert counts['xcodebuild-test.log']>=1450
legacy=(folder/'xcodebuild-test.log').read_text(encoding='utf8',errors='replace')
header_tests=re.findall(r'func (test\w+)\(', (R/'SourceReadSwiftTests/ReaderScrollHeaderTests.swift').read_text(encoding='utf8'))
assert len(header_tests)==6
for name in header_tests:
    assert re.search(r"Test Case .*ReaderScrollHeaderTests.*"+re.escape(name)+r".*passed",legacy),name
exit_tests=re.findall(r'func (test\w+)\(', (R/'SourceReadSwiftTests/ReaderExitSwipeTests.swift').read_text(encoding='utf8'))
assert len(exit_tests)==12
for name in exit_tests:
    assert re.search(r"Test Case .*ReaderExitSwipeTests.*"+re.escape(name)+r".*passed",legacy),name
teardown_tests=re.findall(r'func (test\w+)\(', (R/'SourceReadSwiftTests/ReaderCoverTeardownTests.swift').read_text(encoding='utf8'))
assert len(teardown_tests)==12
for name in teardown_tests:
    for log in [legacy,native]:
        assert re.search(r"Test Case .*ReaderCoverTeardownTests.*"+re.escape(name)+r".*passed",log),name
assert not re.search(r'with [1-9]\d* tests? skipped|Test Case .* skipped',native)
tests=re.findall(r'func (test\w+)\(', (R/'SourceReadSwiftTests/TabChromeRegressionTests.swift').read_text(encoding='utf8'))
for name in tests:
    assert re.search(r"Test Case .*"+re.escape(name)+r".*passed",native),name
ipa=json.loads((O/'IPA_VERIFICATION.json').read_text(encoding='utf8'))
assert ipa['commit']==H and ipa['version']=='1.1.4' and ipa['build']=='125'
assert hashlib.sha256(Path(ipa['path']).read_bytes()).hexdigest()==ipa['sha256']
assert json.loads((O/'VERIFICATION-local.json').read_text(encoding='utf8'))['head']==H
assert json.loads((O/'graphify-out/audit.json').read_text(encoding='utf8'))['head']==H
old=Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.3-build124-unsigned.ipa')
assert hashlib.sha256(old.read_bytes()).hexdigest()=='e888fe076c7f390335030bd08e0be66b39d769c04c00bd655e84dd2bef2ec9c7'
record={'head':H,'version':'1.1.4','build':125,'native_test_counts':counts,
    'release_status':'Crash-stack-directed teardown fix and regression suites passed; physical iOS17.0 retest pending.',
    'crash_proof':json.loads((O/'ios17-video/crash-proof.json').read_text(encoding='utf8')),
    'teardown_cases':teardown_tests,
    'iOS26_special_cases':tests,'scroll_header_cases':header_tests,'exit_and_delay_cases':exit_tests,'iOS26_skipped':0,'failures':0,'ipa':ipa,
    'runs':{n:runs[n]['html_url'] for n in ['iOS','Unsigned IPA']},
    'scope':'Actual dismantle/SwiftUI unmount, queued flick/tap, animator cancellation, silent teardown and reusable cancellation regressions run on both iOS18 and iOS26. Also menu edge exit/delay, prior scroll-header tests, native tabs and full suite. No physical iOS17 device acceptance.',
    'artifacts':{n:str(O/p) for n,p in [('MODIFIED_FILE','MODIFIED_FILE'),('DIFF_FILE','DIFF_FILE.patch'),('VERIFICATION','VERIFICATION.txt'),('ROLLBACK','ROLLBACK.py')]}}
(O/'delivery-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
(O/'VERIFICATION.txt').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n\n'+
    '\n'.join(x for x in native.splitlines() if 'Test Case' in x or 'Executed ' in x or '** TEST' in x)+
    '\n\n'+ '\n'.join(x for x in legacy.splitlines() if 'ReaderCoverTeardownTests' in x or 'ReaderExitSwipeTests' in x or 'ReaderScrollHeaderTests' in x or 'Executed 1450' in x or '** TEST' in x),encoding='utf8')
print(json.dumps(record,ensure_ascii=False,indent=2))
