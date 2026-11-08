from pathlib import Path
import hashlib,json,shutil,subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=Path('F:/SourceReadSwift/recovery-119')
OUT.mkdir(parents=True,exist_ok=True)
manifest=[]
for path in sorted(ROOT.glob('SourceReadSwift/**/*.swift'))+sorted(ROOT.glob('SourceReadSwiftTests/**/*.swift'))+[ROOT/'project.yml']:
    relative=path.relative_to(ROOT);target=OUT/'BASELINE'/relative
    if target.exists():
        assert target.read_bytes()==path.read_bytes(),f'Existing baseline differs: {relative}'
    else:
        target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(path,target)
    manifest.append({'path':relative.as_posix(),'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(OUT/'baseline.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
head=subprocess.check_output(['git','-C',str(ROOT),'rev-parse','HEAD']).decode().strip()
(OUT/'baseline-head.txt').write_text(head+'\n',encoding='utf8')
subprocess.run(['git','-C',str(ROOT),'switch','-c','codex/reader-recovery-119'],check=True)
print('COPY_FIRST',len(manifest),'files',OUT,'HEAD',head)
