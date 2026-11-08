from pathlib import Path
import hashlib,json,shutil,subprocess,sys,time

OUT=Path('F:/SourceReadSwift/recovery-119')
ROOT=Path(__file__).resolve().parents[2]
LOG=[]
def run(args,cwd=None):
    p=subprocess.run(args,cwd=cwd,capture_output=True,text=True,encoding='utf8',errors='replace')
    LOG.append({'command':args,'cwd':str(cwd or ROOT),'stdout':p.stdout,'stderr':p.stderr,'exit_code':p.returncode})
    assert p.returncode==0,p.stderr
    return p
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()

run([sys.executable,str(Path(__file__).with_name('package_evidence.py'))],ROOT)
manifest=json.loads((OUT/'change-manifest.json').read_text(encoding='utf8'))
drill=OUT/'drills'/str(time.time_ns());drill.mkdir(parents=True)
for item in manifest:
    if item['existed']:
        source=OUT/'CANONICAL_BASELINE'/item['path'];target=drill/item['path']
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
def verify(which):
    for item in manifest:
        p=drill/item['path']
        if which=='baseline' and not item['existed']:assert not p.exists(),item['path']
        else:assert digest(p)==item['baseline_git_sha256' if which=='baseline' else 'modified_sha256'],item['path']
    LOG.append({'check':which,'matched_files':len(manifest),'result':'PASS'})
verify('baseline')
for round in range(2):
    run(['git','-c','core.autocrlf=false','-c','core.eol=lf','apply','--check',str(OUT/'DIFF_FILE.patch')],drill)
    run(['git','-c','core.autocrlf=false','-c','core.eol=lf','apply',str(OUT/'DIFF_FILE.patch')],drill)
    verify('modified')
    if round==0:
        run([sys.executable,str(OUT/'ROLLBACK.py'),'--root',str(drill),'--canonical'],drill)
        verify('baseline')
run([sys.executable,str(OUT/'ROLLBACK.py'),'--root',str(drill)],drill)
for item in manifest:
    p=drill/item['path']
    if item['existed']:assert digest(p)==item['baseline_worktree_sha256']
    else:assert not p.exists()
LOG.append({'check':'original worktree bytes restored','matched_files':len(manifest),'result':'PASS'})
run(['git','diff','--check'],ROOT)
data={'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT).decode().strip(),
      'drill_directory':str(drill),'scope':'Byte-level reconstruction and rollback only. Native behavior evidence is recorded separately; no native rollback behavior run claimed.','checks':LOG}
(OUT/'VERIFICATION-local.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
(OUT/'VERIFICATION-local.txt').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
print('PASS: patch applies, modified hashes match, canonical rollback matches, reapply matches, original worktree bytes restored;',len(manifest),'files')
