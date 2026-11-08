from pathlib import Path
import hashlib,json,shutil,subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/recovery-119')
BASE='5686485045b78cfb17c654a2acf8c30c387a73e8'

def git(*args):return subprocess.check_output(['git','-C',str(ROOT),*args])
def sha(data):return hashlib.sha256(data).hexdigest()

def main():
    head=git('rev-parse','HEAD').decode().strip()
    manifest=[]
    for name in git('diff','--name-only',BASE,head).decode().splitlines():
        try:before=git('show',BASE+':'+name)
        except subprocess.CalledProcessError:before=None
        after=git('show',head+':'+name)
        modified=OUT/'MODIFIED_FILE'/name;modified.parent.mkdir(parents=True,exist_ok=True);modified.write_bytes(after)
        original=OUT/'BASELINE'/name
        if before is not None:
            canonical=OUT/'CANONICAL_BASELINE'/name;canonical.parent.mkdir(parents=True,exist_ok=True);canonical.write_bytes(before)
            if not original.exists():original.parent.mkdir(parents=True,exist_ok=True);original.write_bytes(before)
        manifest.append({'path':name,'existed':before is not None,'baseline_git_sha256':sha(before) if before is not None else None,
                         'baseline_worktree_sha256':sha(original.read_bytes()) if original.exists() else None,'modified_sha256':sha(after)})
    (OUT/'change-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
    (OUT/'DIFF_FILE.patch').write_bytes(git('diff','--binary',BASE,head))
    (OUT/'artifact-commit.json').write_text(json.dumps({'baseline':BASE,'modified':head,'files':len(manifest),'patch_bytes':'Git blobs / LF','original_backup':'BASELINE / original worktree bytes'},indent=2),encoding='utf8')
    print('PACKAGED',head,len(manifest),'files',OUT)

if __name__=='__main__':main()
