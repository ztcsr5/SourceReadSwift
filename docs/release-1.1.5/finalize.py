from pathlib import Path
import hashlib, json, re
import ci

O,R,H=ci.OUT,ci.ROOT,ci.ci.HEAD
status=json.loads((O/'ci-status.json').read_text(encoding='utf8'))
assert status['head']==H
runs={r['name']:r for r in status['runs']}
assert all(runs[n]['conclusion']=='success' and runs[n]['head_sha']==H for n in ['iOS','Unsigned IPA'])
folder=O/'native-evidence'/H
counts={};logs={}
for name in ['xcodebuild-test.log','native-tab-test.log']:
    log=(folder/name).read_text(encoding='utf8',errors='replace');logs[name]=log
    assert '** TEST SUCCEEDED **' in log,name
    rows=re.findall(r'Executed (\d+) tests?,(?: with \d+ tests? skipped and)? with (\d+) failures?',log)
    rows+=re.findall(r'Executed (\d+) tests?, with \d+ tests? skipped and (\d+) failures?',log)
    assert rows and all(int(f)==0 for _,f in rows),(name,rows)
    counts[name]=max(int(n) for n,_ in rows)
legacy,native=logs['xcodebuild-test.log'],logs['native-tab-test.log']
assert not re.search(r'with [1-9]\d* tests? skipped|Test Case .* skipped',native)
suites={}
for suite in ['AppLayoutDensityTests','SourceOrganizationTests','ReaderTocPerformanceTests',
              'ReaderCoverTeardownTests','TabChromeRegressionTests','ReaderScrollHeaderTests','ReaderExitSwipeTests']:
    tests=re.findall(r'func (test\w+)\(', (R/f'SourceReadSwiftTests/{suite}.swift').read_text(encoding='utf8'))
    suites[suite]=tests
    for test in tests:
        selected=[legacy] if suite in ['ReaderScrollHeaderTests','ReaderExitSwipeTests'] else [legacy,native]
        if suite=='TabChromeRegressionTests': selected=[native]
        for log in selected:
            assert re.search(r'Test Case .*'+suite+'.*'+re.escape(test)+r'.*passed',log),(suite,test)
expected=15+sum(len(suites[s]) for s in ['AppLayoutDensityTests','SourceOrganizationTests','ReaderTocPerformanceTests'])
assert counts['native-tab-test.log']==expected,(counts,expected)
assert counts['xcodebuild-test.log']>=1450+len(suites['AppLayoutDensityTests'])+len(suites['SourceOrganizationTests'])+len(suites['ReaderTocPerformanceTests'])-4
for runtime in ['ios18-ui','ios26-ui']:
    assert len(list((folder/runtime).glob('*.png')))>=10,runtime
visual=json.loads((folder/'visual-review.json').read_text(encoding='utf8'))
assert visual['head']==H and visual['status']=='PASS'
ipa=json.loads((O/'IPA_VERIFICATION.json').read_text(encoding='utf8'))
assert ipa['commit']==H and ipa['version']=='1.1.5' and ipa['build']=='126'
assert hashlib.sha256(Path(ipa['path']).read_bytes()).hexdigest()==ipa['sha256']
assert json.loads((O/'VERIFICATION-local.json').read_text(encoding='utf8'))['head']==H
assert json.loads((O/'graphify-out/audit.json').read_text(encoding='utf8'))['head']==H
assert hashlib.sha256(Path('C:/Users/Edc21/Desktop/SourceReadSwift-1.1.4-build125-unsigned.ipa').read_bytes()).hexdigest()=='e5ed29762106d680968d659a46557605f63a0efdbcfc0bded5c92a4ec6a551f1'
record={'head':H,'version':'1.1.5','build':126,'native_test_counts':counts,'failures':0,'iOS26_skipped':0,
        'verified_suites':suites,'visual_review':visual,'ipa':ipa,
        'runs':{n:runs[n]['html_url'] for n in ['iOS','Unsigned IPA']},
        'scope':'Main-page layout measurements/screenshots; TOC sort target and cache; source grouping/order persistence and failed-save tests; full and native tab/reader teardown regressions. Physical iOS16/17 acceptance remains pending.',
        'artifacts':{n:str(O/p) for n,p in [('MODIFIED_FILE','MODIFIED_FILE'),('DIFF_FILE','DIFF_FILE.patch'),('VERIFICATION','VERIFICATION.txt'),('ROLLBACK','ROLLBACK.py')]}}
(O/'delivery-verification.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
(O/'VERIFICATION.txt').write_text(json.dumps(record,ensure_ascii=False,indent=2)+'\n\n'+
    '\n'.join(x for x in native.splitlines() if 'Test Case' in x or 'Executed ' in x or '** TEST' in x)+
    '\n\n'+'\n'.join(x for x in legacy.splitlines() if any(k in x for k in ['TOC 10000','TOC projection','Executed ', '** TEST'])),encoding='utf8')
print(json.dumps({k:record[k] for k in ['head','version','build','native_test_counts','failures','ipa','runs']},ensure_ascii=False,indent=2))
