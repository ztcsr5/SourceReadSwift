import importlib.util, json, pathlib, subprocess, hashlib, shutil
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = pathlib.Path('F:/SourceReadSwift/reader-toc-121')
OUT.mkdir(parents=True, exist_ok=True)
files = subprocess.check_output(['git', 'ls-files'], cwd=ROOT, text=True).splitlines()
manifest = {}
for name in files:
    src = ROOT / name
    if not src.is_file(): continue
    dest = OUT / 'BASELINE' / name
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dest)
    manifest[name] = hashlib.sha256(dest.read_bytes()).hexdigest()
(OUT / 'baseline.json').write_text(json.dumps({'head': subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(), 'files':manifest},indent=2),encoding='utf-8')
print({n:bool(importlib.util.find_spec(n)) for n in ['cv2','imageio','imageio_ffmpeg','PIL']})
video=pathlib.Path('C:/Users/Edc21/Documents/Tencent Files/2865460461/nt_qq/nt_data/Video/2026-10/Ori/56f63ab59cd249af0d690b374e0a839f.mp4')
print('video',video.exists(),video.stat().st_size if video.exists() else None)
for base in [ROOT,ROOT.parent,pathlib.Path('C:/Users/Edc21/Documents/IOS')]:
    p=base/'AGENTS.md'
    if p.exists(): print('AGENTS',p,'\n',p.read_text(encoding='utf-8'))
graph=pathlib.Path('F:/SourceReadSwift/release-1.1.0/graphify-out/graph.json')
if graph.exists():
    data=json.loads(graph.read_text(encoding='utf-8'))
    nodes=data.get('nodes',[])
    matches=[n for n in nodes if any(s in json.dumps(n) for s in ['TocFilterCache','TocChapterRow','ChapterListPresenter','BookDetailAllChaptersView','SettingsView'])]
    print('GRAPH ORIENTATION',json.dumps(matches[:12],ensure_ascii=False)[:7000])
