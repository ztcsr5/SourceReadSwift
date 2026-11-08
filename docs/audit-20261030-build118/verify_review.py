"""Verify audit artifacts and prove business sources match the initial baseline."""
import hashlib
import json
import py_compile
import shutil
import subprocess
from datetime import datetime,timezone,timedelta
from pathlib import Path

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[1]

def main():
    baseline=json.loads((OUT/'source-baseline.json').read_text(encoding='utf8'))
    changed=[]
    for item in baseline:
        path=ROOT/item['path']
        actual=hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else None
        if actual!=item['sha256']:changed.append({'path':item['path'],'expected':item['sha256'],'actual':actual})
    required=['PROJECT_REVIEW.md','ISSUE_REGISTER.md','history-review.md','pagination-audit.md','flip-audit.md','project-audit.md','INVENTORY.md','source-inventory.json','source-baseline.json','chat-extraction.json','codex-history-manifest.json','ci-readonly-metadata.json','pagination-model-results.json','flip-model-results.json','graph.json','graph.html','GRAPH_REPORT.md','video-contact.jpg']
    missing=[name for name in required if not (OUT/name).is_file()]
    parsing=[]
    for path in OUT.glob('*.json'):
        json.loads(path.read_text(encoding='utf8'));parsing.append(path.name)
    for path in OUT.glob('*.py'):py_compile.compile(str(path),doraise=True)
    executions=[]
    for args in [['git','-C',str(ROOT),'diff','--check'],['python','-X','utf8',str(OUT/'pagination-model-check.py')],['python','-X','utf8',str(OUT/'check_flip_model.py')]]:
        proc=subprocess.run(args,capture_output=True,text=True,encoding='utf8')
        executions.append({'command':args,'exit_code':proc.returncode,'stdout':proc.stdout,'stderr':proc.stderr})
    # Graphify created this parser cache during this audit (absent at initial status).
    # Relocate only this exact generated folder, after checking both absolute paths.
    src=ROOT/'SourceReadSwift/Features/Reader/graphify-out'
    dst=OUT/'graphify-generated-cache'
    relocated=False
    if src.exists() and not dst.exists():
        source=src.resolve();destination=dst.resolve()
        assert source==ROOT.resolve()/'SourceReadSwift/Features/Reader/graphify-out'
        assert destination.is_relative_to(OUT.resolve())
        print('MOVE VERIFIED',source,'->',destination)
        shutil.move(str(source),str(destination));relocated=True
    head=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD']).decode().strip()
    status=subprocess.check_output(['git','-C',str(ROOT),'status','--short']).decode('utf8')
    result={'checked_at':datetime.now(timezone(timedelta(hours=8))).isoformat(),'head':head,'baseline_files_checked':len(baseline),'business_sources_unchanged':not changed,'changed_baseline_files':changed,'missing_artifacts':missing,'valid_json_files':len(parsing),'python_scripts_compile':'PASS','executions':executions,'parser_cache_relocated_to_audit':relocated,'git_status':status,'not_run':['New iOS/Xcode build','New XCTest run','iOS simulator/physical-device UI reproduction','Instruments frame-time and memory measurements'],'note':'Python counterexample models and source assertions are not Swift/UIKit tests.'}
    result['pass']=not changed and not missing and all(e['exit_code']==0 for e in executions)
    (OUT/'VERIFICATION.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
    print(json.dumps({k:v for k,v in result.items() if k not in ('executions','git_status')},ensure_ascii=False,indent=2))
    if not result['pass']:raise SystemExit(1)

if __name__=='__main__':main()
