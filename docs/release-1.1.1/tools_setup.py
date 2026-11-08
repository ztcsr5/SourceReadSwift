from pathlib import Path
R=Path(__file__).resolve().parents[2]
for name in ['ci.py','syntax_compare.py']:
 s=(R/'docs/reader-toc-121'/name).read_text(encoding='utf-8')
 s=s.replace('F:/SourceReadSwift/reader-toc-121','F:/SourceReadSwift/release-1.1.1').replace('codex%2Frelease-1.1.0','codex%2Frelease-1.1.1').replace('HEAD:codex/release-1.1.0','HEAD:codex/release-1.1.1').replace('docs/reader-toc-121/RECOVERY.md','docs/release-1.1.1/RECOVERY.md').replace('de82995','f808c79')
 if name=='ci.py':
  s=s.replace("'project.yml','docs/release-1.1.1/RECOVERY.md'","'project.yml','.github/workflows/unsigned-ipa.yml','docs/release-1.1.1/RECOVERY.md'")
 if name=='syntax_compare.py':
  s=s.replace('rows=[]',"names += subprocess.check_output(['git','ls-files','--others','--exclude-standard','SourceReadSwift','SourceReadSwiftTests'],cwd=R).decode().splitlines()\nrows=[]")
 (R/'docs/release-1.1.1'/name).write_text(s,encoding='utf-8')
print('new branch helpers ready')
